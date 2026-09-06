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

function formatDate(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${dd}`
}

async function loadData() {
  if (!userStore.classId) return
  loading.value = true
  try {
    const { data: stuRes } = await supabase
      .from('students')
      .select('id, student_name')
      .eq('class_id', userStore.classId)
      .order('student_name', { ascending: true })
    students.value = (stuRes ?? []) as StudentRow[]

    const { data: subRes } = await supabase
      .from('homework_subjects')
      .select('*')
      .eq('school_id', userStore.schoolId)
      .order('sort_order', { ascending: true })
    subjects.value = (subRes ?? []) as SubjectRow[]

    const { data: recData } = await supabase.from('homework_records').select('*')
    const { data: noteData } = await supabase.from('homework_notes').select('*')

    const rows = (recData ?? []) as HomeworkRecord[]
    const stuMap: Record<string, string> = {}
    students.value.forEach((s) => { stuMap[s.id] = s.student_name })
    const subMap: Record<string, string> = {}
    subjects.value.forEach((s) => { subMap[s.id] = s.subject_name })
    rows.forEach((r) => {
      if (!r.student_name) r.student_name = stuMap[r.student_id]
      if (!r.subject_name) r.subject_name = subMap[r.subject_id]
    })
    allRecords.value = rows

    // 备注
    const notes = (noteData ?? []) as HomeworkNote[]
    notes.forEach((n) => { if (!n.subject_name) n.subject_name = subMap[n.subject_id] })
    allNotes.value = notes
  } catch (err: any) {
    ElMessage.error(err.message || '加载数据失败')
  } finally {
    loading.value = false
  }
}

// 某天的完成率
function dayCompletion(dateStr: string): { total: number; done: number; pct: number } {
  const rows = allRecords.value.filter((r) => r.record_date === dateStr)
  if (rows.length === 0) return { total: 0, done: 0, pct: -1 }
  const total = rows.length
  const done = rows.filter((r) => r.is_done).length
  return { total, done, pct: +((done / total) * 100).toFixed(0) }
}

// 某天的矩阵
const dayMatrix = computed(() => {
  const rows = allRecords.value.filter((r) => r.record_date === selectedDate.value)
  const subjectIds = Array.from(new Set(rows.map((r) => r.subject_id))).sort()
  let sortedSubjects = subjects.value.filter((s) => subjectIds.includes(s.id))
  // 如果当天还没有记录，显示所有已配置学科（方便老师录入备注）
  if (sortedSubjects.length === 0) sortedSubjects = subjects.value
  const studentIds = Array.from(new Set(rows.map((r) => r.student_id)))
  const sortedStudents = students.value.filter((s) => studentIds.includes(s.id))
  const recMap = new Map<string, HomeworkRecord>()
  rows.forEach((r) => recMap.set(`${r.student_id}|${r.subject_id}`, r))
  return { sortedStudents, sortedSubjects, recMap }
})

const dayStats = computed(() => dayCompletion(selectedDate.value))

// 当天的备注（按学科）
const dayNotesMap = computed(() => {
  const map = new Map<string, HomeworkNote>()
  allNotes.value
    .filter((n) => n.record_date === selectedDate.value)
    .forEach((n) => map.set(n.subject_id, n))
  return map
})

// ===== 备注保存 =====
async function saveNote(subjId: string, content: string) {
  if (!userStore.classId || !content.trim()) return
  const subjectName = subjects.value.find((s) => s.id === subjId)?.subject_name
  const existing = dayNotesMap.value.get(subjId)
  try {
    if (existing) {
      const { error } = await supabase
        .from('homework_notes')
        .update({ content: content.trim() })
        .eq('id', existing.id)
      if (error) throw error
    } else {
      const { error } = await supabase.from('homework_notes').insert({
        school_id: userStore.schoolId,
        class_id: userStore.classId,
        record_date: selectedDate.value,
        subject_id: subjId,
        subject_name: subjectName,
        content: content.trim(),
      })
      if (error) throw error
    }
    ElMessage.success('备注已保存')
    await loadData()
  } catch (err: any) {
    ElMessage.error(err.message || '保存失败')
  }
}

async function toggleDone(stuId: string, subjId: string) {
  const key = `${stuId}|${subjId}`
  const existing = dayMatrix.value.recMap.get(key)
  if (existing) {
    const { error } = await supabase
      .from('homework_records')
      .update({ is_done: !existing.is_done, update_time: new Date().toISOString() })
      .eq('id', existing.id)
    if (error) { ElMessage.error(error.message); return }
  } else {
    const studentName = students.value.find((s) => s.id === stuId)?.student_name
    const subjectName = subjects.value.find((s) => s.id === subjId)?.subject_name
    const { error } = await supabase.from('homework_records').insert({
      school_id: userStore.schoolId,
      class_id: userStore.classId,
      student_id: stuId,
      subject_id: subjId,
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
function handleExport() {
  const { sortedStudents, sortedSubjects, recMap } = dayMatrix.value
  if (sortedStudents.length === 0) {
    ElMessage.warning('当天暂无学生作业数据')
    return
  }

  const filterSubjId = exportSubject.value
  const subjectsToExport = filterSubjId === 'all'
    ? sortedSubjects
    : sortedSubjects.filter((s) => s.id === filterSubjId)

  if (subjectsToExport.length === 0) {
    ElMessage.warning('所选学科当天暂无数据')
    return
  }

  // 准备工作表数据
  const sheets: { name: string; data: any[][] }[] = []

  for (const subj of subjectsToExport) {
    const note = dayNotesMap.value.get(subj.id)
    const header = ['学生姓名', subj.subject_name + '（完成）', subj.subject_name + '（备注）']
    const body: any[][] = sortedStudents.map((stu) => {
      const r = recMap.get(`${stu.id}|${subj.id}`)
      return [stu.student_name, r ? (r.is_done ? '是' : '否') : '', note?.content || '']
    })
    sheets.push({ name: subj.subject_name, data: [header, ...body] })
  }

  // 生成 xlsx
  const wb = XLSX.utils.book_new()
  for (const sh of sheets) {
    const ws = XLSX.utils.aoa_to_sheet(sh.data)
    // 列宽
    ws['!cols'] = [{ wch: 12 }, { wch: 12 }, { wch: 40 }]
    XLSX.utils.book_append_sheet(wb, ws, sh.name.substring(0, 31))
  }
  XLSX.writeFile(wb, `作业_${selectedDate.value}_${exportSubject.value === 'all' ? '全部学科' : sheets[0].name}_${Date.now()}.xlsx`)
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
            v-for="s in subjects"
            :key="s.id"
            :label="s.subject_name"
            :value="s.id"
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
              <div v-for="subj in subjects" :key="subj.id" class="note-row">
                <div class="note-label">{{ subj.subject_name }}</div>
                <div class="note-input-wrap">
                  <el-input
                    :model-value="dayNotesMap.get(subj.id)?.content || ''"
                    type="textarea"
                    :rows="2"
                    :placeholder="`输入 ${subj.subject_name} 今日作业内容…`"
                    resize="none"
                    @blur="saveNote(subj.id, ($event.target as HTMLInputElement).value)"
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
                v-for="subj in dayMatrix.sortedSubjects"
                :key="subj.id"
                :label="subj.subject_name"
                align="center"
              >
                <template #default="{ row }">
                  <div
                    class="hw-toggle"
                    :class="{ done: dayMatrix.recMap.get(`${row.id}|${subj.id}`)?.is_done }"
                    @click="toggleDone(row.id, subj.id)"
                  >
                    {{ dayMatrix.recMap.get(`${row.id}|${subj.id}`)?.is_done ? '✔' : '○' }}
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
