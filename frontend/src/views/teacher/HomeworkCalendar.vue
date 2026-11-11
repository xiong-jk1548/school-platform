<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { ElMessage } from 'element-plus'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'
import * as XLSX from 'xlsx'

const userStore = useUserStore()

interface HomeworkRecord {
  id: string
  student_id: string
  student_name?: string
  subject_id: string
  subject_name?: string
  record_date: string
  is_done: boolean
}
interface HomeworkNote {
  id: string
  school_id: string
  class_id: string
  record_date: string
  subject_id: string
  subject_name?: string
  content: string
}
interface StudentRow {
  id: string
  student_name: string
}
interface SubjectRow {
  id: string
  subject_name: string
  sort_order: number
}

const students = ref<StudentRow[]>([])
const subjects = ref<SubjectRow[]>([])
const allRecords = ref<HomeworkRecord[]>([])
const allNotes = ref<HomeworkNote[]>([])
const loading = ref(false)

const selectedDate = ref(formatDate(new Date()))

// 导出筛选
const exportSubject = ref<string>('all')

/**
 * 把 Date 对象格式化为 YYYY-MM-DD（用于 record_date 查询与文件名）
 * @param date 待格式化的日期对象
 * @returns 形如 2026-09-06 的日期字符串
 */
function formatDate(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

/**
 * 一次性加载学生、作业科目、作业完成记录与作业备注，并补齐姓名/科目名
 * @returns 无返回值（副作用：写入 students、subjects、allRecords、allNotes，并维护 loading）
 */
async function loadData() {
  if (!userStore.classId) return
  loading.value = true
  try {
    const { data: studentRows } = await supabase
      .from('students')
      .select('id, student_name')
      .eq('class_id', userStore.classId)
      .order('student_name', { ascending: true })
    students.value = (studentRows ?? []) as StudentRow[]

    const { data: subjectRows } = await supabase
      .from('homework_subjects')
      .select('*')
      .eq('school_id', userStore.schoolId)
      .order('sort_order', { ascending: true })
    subjects.value = (subjectRows ?? []) as SubjectRow[]

    // ⚠️ 必须显式按 class_id 收窄：作业的 RLS 是**按学校**放行的（教师可跨班协作），
    // 不加这个条件会把全校各班的作业记录/备注混进本页（本页只展示本班日历）。
    const { data: recordRows } = await supabase
      .from('homework_records')
      .select('*')
      .eq('class_id', userStore.classId)
    const { data: noteRows } = await supabase
      .from('homework_notes')
      .select('*')
      .eq('class_id', userStore.classId)

    const recordList = (recordRows ?? []) as HomeworkRecord[]
    const stuMap: Record<string, string> = {}
    students.value.forEach((student) => { stuMap[student.id] = student.student_name })
    const subMap: Record<string, string> = {}
    subjects.value.forEach((subject) => { subMap[subject.id] = subject.subject_name })
    recordList.forEach((record) => {
      if (!record.student_name) record.student_name = stuMap[record.student_id]
      if (!record.subject_name) record.subject_name = subMap[record.subject_id]
    })
    allRecords.value = recordList

    // 备注
    const noteList = (noteRows ?? []) as HomeworkNote[]
    noteList.forEach((note) => { if (!note.subject_name) note.subject_name = subMap[note.subject_id] })
    allNotes.value = noteList
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载数据失败')
  } finally {
    loading.value = false
  }
}

/**
 * 统计某一天的作业完成率
 * @param dateStr 目标日期（YYYY-MM-DD）
 * @returns { total, done, pct }；当天无记录时返回 { total: 0, done: 0, pct: -1 }
 */
function dayCompletion(dateStr: string): { total: number; done: number; pct: number } {
  const dayRecords = allRecords.value.filter((record) => record.record_date === dateStr)
  if (dayRecords.length === 0) return { total: 0, done: 0, pct: -1 }
  const total = dayRecords.length
  const done = dayRecords.filter((record) => record.is_done).length
  return { total, done, pct: +((done / total) * 100).toFixed(0) }
}

// 某天的矩阵
const dayMatrix = computed(() => {
  const dayRecords = allRecords.value.filter((record) => record.record_date === selectedDate.value)
  const subjectIds = Array.from(new Set(dayRecords.map((record) => record.subject_id))).sort()
  let sortedSubjects = subjects.value.filter((subject) => subjectIds.includes(subject.id))
  // 如果当天还没有记录，显示所有已配置学科（方便老师录入备注）
  if (sortedSubjects.length === 0) sortedSubjects = subjects.value
  const studentIds = Array.from(new Set(dayRecords.map((record) => record.student_id)))
  const sortedStudents = students.value.filter((student) => studentIds.includes(student.id))
  const recMap = new Map<string, HomeworkRecord>()
  dayRecords.forEach((record) => recMap.set(`${record.student_id}|${record.subject_id}`, record))
  return { sortedStudents, sortedSubjects, recMap }
})

const dayStats = computed(() => dayCompletion(selectedDate.value))

// 当天的备注（按学科）
const dayNotesMap = computed(() => {
  const notesBySubject = new Map<string, HomeworkNote>()
  allNotes.value
    .filter((note) => note.record_date === selectedDate.value)
    .forEach((note) => notesBySubject.set(note.subject_id, note))
  return notesBySubject
})

// ===== 备注保存 =====
/**
 * 保存某学科当天的作业内容备注：已有备注走更新、没有则新增
 * @param subjectId 作业科目 id
 * @param content 备注文本（为空时不保存）
 * @returns 无返回值（副作用：写库、提示、重新加载数据）
 */
async function saveNote(subjectId: string, content: string) {
  if (!userStore.classId || !content.trim()) return
  const subjectName = subjects.value.find((subject) => subject.id === subjectId)?.subject_name
  const existingNote = dayNotesMap.value.get(subjectId)
  try {
    if (existingNote) {
      const { error } = await supabase
        .from('homework_notes')
        .update({ content: content.trim() })
        .eq('id', existingNote.id)
      if (error) throw error
    } else {
      const { error } = await supabase.from('homework_notes').insert({
        school_id: userStore.schoolId,
        class_id: userStore.classId,
        record_date: selectedDate.value,
        subject_id: subjectId,
        subject_name: subjectName,
        content: content.trim(),
      })
      if (error) throw error
    }
    ElMessage.success('备注已保存')
    await loadData()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存失败')
  }
}

/**
 * 切换某个学生某学科的作业完成状态：已有记录取反更新，没有则新增一条「已完成」
 * @param studentId 学生 id
 * @param subjectId 作业科目 id
 * @returns 无返回值（副作用：写库、提示、重新加载数据）
 */
async function toggleDone(studentId: string, subjectId: string) {
  const recordKey = `${studentId}|${subjectId}`
  const existingRecord = dayMatrix.value.recMap.get(recordKey)
  if (existingRecord) {
    const { error } = await supabase
      .from('homework_records')
      .update({ is_done: !existingRecord.is_done, update_time: new Date().toISOString() })
      .eq('id', existingRecord.id)
    if (error) { ElMessage.error(error.message); return }
  } else {
    const studentName = students.value.find((student) => student.id === studentId)?.student_name
    const subjectName = subjects.value.find((subject) => subject.id === subjectId)?.subject_name
    const { error } = await supabase.from('homework_records').insert({
      school_id: userStore.schoolId,
      class_id: userStore.classId,
      student_id: studentId,
      subject_id: subjectId,
      record_date: selectedDate.value,
      is_done: true,
      update_user_id: (await supabase.auth.getSession()).data.session?.user.id,
      update_time: new Date().toISOString(),
      student_name: studentName,
      subject_name: subjectName,
    })
    if (error) { ElMessage.error(error.message); return }
  }
  ElMessage.success('已更新')
  await loadData()
}

// ===== 按学科导出 =====
/**
 * 导出所选日期（可再按学科筛选）的作业完成情况与备注为多 Sheet 的 Excel
 * 每个学科一个 Sheet，列为：学生姓名 / 完成 / 备注
 */
function handleExport() {
  const { sortedStudents, sortedSubjects, recMap } = dayMatrix.value
  if (sortedStudents.length === 0) {
    ElMessage.warning('当天暂无学生作业数据')
    return
  }

  const filterSubjectId = exportSubject.value
  const subjectsToExport = filterSubjectId === 'all'
    ? sortedSubjects
    : sortedSubjects.filter((subject) => subject.id === filterSubjectId)

  if (subjectsToExport.length === 0) {
    ElMessage.warning('所选学科当天暂无数据')
    return
  }

  // 准备工作表数据
  const sheetList: { name: string; data: any[][] }[] = []

  for (const subject of subjectsToExport) {
    const note = dayNotesMap.value.get(subject.id)
    const headerRow = ['学生姓名', subject.subject_name + '（完成）', subject.subject_name + '（备注）']
    const bodyRows: any[][] = sortedStudents.map((student) => {
      const record = recMap.get(`${student.id}|${subject.id}`)
      return [student.student_name, record ? (record.is_done ? '是' : '否') : '', note?.content || '']
    })
    sheetList.push({ name: subject.subject_name, data: [headerRow, ...bodyRows] })
  }

  // 生成 xlsx
  const workbook = XLSX.utils.book_new()
  for (const sheetItem of sheetList) {
    const worksheet = XLSX.utils.aoa_to_sheet(sheetItem.data)
    // 列宽
    worksheet['!cols'] = [{ wch: 12 }, { wch: 12 }, { wch: 40 }]
    XLSX.utils.book_append_sheet(workbook, worksheet, sheetItem.name.substring(0, 31))
  }
  XLSX.writeFile(workbook, `作业_${selectedDate.value}_${exportSubject.value === 'all' ? '全部学科' : sheetList[0].name}_${Date.now()}.xlsx`)
  ElMessage.success('导出成功')
}

onMounted(loadData)
</script>

<template>
  <div class="hw-calendar">
    <!-- 顶部：紧凑日期选择 + 工具栏 -->
    <div class="top-bar">
      <div class="top-left">
        <span class="top-title">作业日历</span>
        <el-date-picker
          v-model="selectedDate"
          type="date"
          value-format="YYYY-MM-DD"
          placeholder="选择日期"
          style="width: 160px"
          size="default"
        />
      </div>
      <div class="top-right">
        <span class="export-label">导出学科：</span>
        <el-select v-model="exportSubject" style="width: 120px" size="default">
          <el-option label="全部学科" value="all" />
          <el-option
            v-for="subject in subjects"
            :key="subject.id"
            :label="subject.subject_name"
            :value="subject.id"
          />
        </el-select>
        <el-button @click="handleExport">导出当天 Excel</el-button>
      </div>
    </div>

    <!-- 当天详情（占满整行） -->
    <div class="day-card">
          <div class="day-header">
            <span class="day-title">{{ selectedDate }}</span>
            <el-tag
              v-if="dayStats.total > 0"
              :type="dayStats.pct >= 80 ? 'success' : dayStats.pct >= 50 ? 'warning' : 'danger'"
              effect="dark"
            >
              完成率 {{ dayStats.pct }}%（{{ dayStats.done }}/{{ dayStats.total }}）
            </el-tag>
            <el-tag v-else type="info" effect="plain">当天暂无作业数据</el-tag>
          </div>

          <!-- 作业备注（按学科） -->
          <div v-if="subjects.length > 0" class="notes-area">
            <div class="notes-title">📝 今日作业内容（按学科）</div>
            <div class="notes-list">
              <div v-for="subject in subjects" :key="subject.id" class="note-row">
                <div class="note-label">{{ subject.subject_name }}</div>
                <div class="note-input-wrap">
                  <el-input
                    :model-value="dayNotesMap.get(subject.id)?.content || ''"
                    type="textarea"
                    :rows="2"
                    :placeholder="`输入 ${subject.subject_name} 今日作业内容…`"
                    resize="none"
                    @blur="saveNote(subject.id, ($event.target as HTMLInputElement).value)"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- 完成情况矩阵 -->
          <div v-if="dayMatrix.sortedStudents.length > 0" class="day-matrix">
            <el-table :data="dayMatrix.sortedStudents" border stripe size="default" style="width: 100%">
              <el-table-column prop="student_name" label="学生" width="100" fixed="left" />
              <el-table-column
                v-for="subject in dayMatrix.sortedSubjects"
                :key="subject.id"
                :label="subject.subject_name"
                align="center"
              >
                <template #default="{ row: studentRow }">
                  <div
                    class="hw-toggle"
                    :class="{ done: dayMatrix.recMap.get(`${studentRow.id}|${subject.id}`)?.is_done }"
                    @click="toggleDone(studentRow.id, subject.id)"
                  >
                    {{ dayMatrix.recMap.get(`${studentRow.id}|${subject.id}`)?.is_done ? '✔' : '○' }}
                  </div>
                </template>
              </el-table-column>
            </el-table>
          </div>
          <el-empty v-else description="当天暂无学生作业记录" :image-size="80" />
        </div>
  </div>
</template>

<style scoped>
.hw-calendar { padding: 0; }

.top-bar {
  display: flex; justify-content: space-between; align-items: center;
  margin-bottom: 16px;
  flex-wrap: wrap; gap: 8px;
}
.top-left { display: flex; align-items: center; gap: 12px; }
.top-title { font-size: 16px; font-weight: 600; color: #1F2937; }
.top-right { display: flex; align-items: center; gap: 8px; }
.export-label { font-size: 13px; color: #6B7280; }

.day-card {
  background: #FFFFFF;
  border-radius: 12px;
  border: 1px solid #E5E9F0;
  box-shadow: 0 2px 8px rgba(30, 58, 138, 0.04);
  padding: 16px;
}

/* 右侧 */
.day-header {
  display: flex; justify-content: space-between; align-items: center;
  margin-bottom: 14px;
}
.day-title { font-size: 16px; font-weight: 600; color: #1F2937; }

/* 备注区 */
.notes-area {
  margin-bottom: 16px;
  padding: 12px;
  background: #F8FAFF;
  border-radius: 10px;
  border: 1px dashed #C7D4FF;
}
.notes-title {
  font-size: 13px; font-weight: 600; color: #2B5CE6; margin-bottom: 10px;
}
.notes-list { display: flex; flex-direction: column; gap: 8px; }
.note-row { display: flex; gap: 10px; align-items: flex-start; }
.note-label {
  flex-shrink: 0;
  width: 56px;
  font-size: 13px; font-weight: 500; color: #374151;
  padding-top: 6px;
}
.note-input-wrap { flex: 1; }

.hw-toggle {
  display: inline-flex; align-items: center; justify-content: center;
  width: 32px; height: 32px; border-radius: 50%;
  cursor: pointer; transition: all 0.15s;
  background: #F3F4F6; color: #9CA3AF; font-size: 16px; font-weight: 600;
}
.hw-toggle:hover { background: #E5E7EB; }
.hw-toggle.done { background: #10B981; color: #fff; }
</style>
