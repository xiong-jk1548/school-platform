<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { Calendar, Setting } from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'
import SubjectManageDialog from './SubjectManageDialog.vue'

const userStore = useUserStore()

interface StudentRow {
  id: string
  student_name: string
  name?: string
  student_no?: string
  class_id?: string
}

interface SubjectRow {
  id: string
  subject_name: string
  name?: string
  sort_order: number
}

interface RecordRow {
  id: string
  student_id: string
  subject_id: string
  is_done: boolean
}

interface NoteRow {
  id: string
  subject_id: string
  subject_name?: string
  content: string
}

const selectedDate = ref<string>(formatDate(new Date()))
const searchKeyword = ref('')
const filterSubjectId = ref<string>('')
const showIncompleteOnly = ref(false)
const boardLoading = ref(false)
const subjectList = ref<SubjectRow[]>([])
const allStudentList = ref<StudentRow[]>([])
const recordMap = ref<Map<string, RecordRow>>(new Map())
const noteList = ref<NoteRow[]>([])  // 今日作业备注
// 快速录入条的本地草稿（键 = 科目 ID）。
// 输入必须先落在本地变量上：el-input 在每次输入后会按 props.modelValue 回写原生输入框，
// 若直接绑 noteList（只读派生值），敲一个字就会被回写成旧值，表现为"备注框打不进字"。
const noteDraft = ref<Record<string, string>>({})

/**
 * 用「科目列表 + 已保存备注」重建本地草稿。
 * 科目未布置作业时补空串，保证每个科目都有键，v-model 不会落到 undefined。
 * @returns 无返回值（副作用：写入 noteDraft）
 */
function syncNoteDraft() {
  const draft: Record<string, string> = {}
  for (const subjectRow of subjectList.value) draft[subjectRow.id] = ''
  for (const noteItem of noteList.value) draft[noteItem.subject_id] = noteItem.content
  noteDraft.value = draft
}

const filterClassId = ref<string>('')
const schoolClasses = ref<{ id: string; class_name: string }[]>([])

/**
 * 当前操作的班级。
 * 作业是**校内公开**的数据（RLS 已按 school_id 放行），教师可以跨班查看/登记，
 * 因此教师也走下拉选择，未选时回落到自己绑定的班。
 */
const effectiveClassId = computed<string | null>(() => {
  if (userStore.role === 'school_admin') return filterClassId.value || null
  return filterClassId.value || userStore.boundClassId || null
})

/**
 * 加载班级下拉数据：本校全部班级（教师可跨班协作，故与学校管理员一致）。
 * 教师默认选中自己的班，学校管理员默认"全部"。
 * @returns 无返回值（副作用：写入 schoolClasses 与 filterClassId）
 */
async function loadSchoolClasses() {
  if (!userStore.schoolId) return
  try {
    const { data: classRows, error } = await supabase
      .from('classes')
      .select('id, class_name')
      .eq('school_id', userStore.schoolId)
    if (error) throw error
    schoolClasses.value = (classRows ?? []) as { id: string; class_name: string }[]
    if (userStore.role !== 'school_admin' && !filterClassId.value) {
      filterClassId.value = userStore.boundClassId || ''
    }
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载班级列表失败')
  }
}

// 卡片编辑状态
const editingSubjectId = ref<string | null>(null)
const editingContent = ref('')

/**
 * 依据科目名称生成一个稳定的展示配色，同一科目每次渲染颜色一致。
 * @param subjectId 科目 ID
 * @returns 十六进制颜色值；科目不存在时返回默认主色
 */
function subjectColor(subjectId: string): string {
  const subjectRow = subjectList.value.find((subjectItem) => subjectItem.id === subjectId)
  if (!subjectRow) return '#2B5CE6'
  // 给每个学科按其名字生成稳定颜色
  const palette = ['#2B5CE6', '#10B981', '#F59E0B', '#EF4444', '#8B5CF6', '#06B6D4', '#EC4899']
  let nameCharSum = 0
  for (let charIndex = 0; charIndex < subjectRow.subject_name.length; charIndex++) nameCharSum += subjectRow.subject_name.charCodeAt(charIndex)
  return palette[nameCharSum % palette.length]
}

/**
 * 进入某个科目的作业卡片编辑态，并把已保存的备注内容回填到输入框。
 * @param subjectRow 被编辑的科目行
 * @returns 无返回值（副作用：写入 editingSubjectId 与 editingContent）
 */
function startEditCard(subjectRow: SubjectRow) {
  editingSubjectId.value = subjectRow.id
  editingContent.value = noteList.value.find((noteItem) => noteItem.subject_id === subjectRow.id)?.content || ''
}
/** 取消卡片编辑态并清空草稿内容 */
function cancelEditCard() {
  editingSubjectId.value = null
  editingContent.value = ''
}
/** 保存卡片编辑内容（空内容等价于删除备注），随后退出编辑态 */
async function confirmEditCard() {
  if (!editingSubjectId.value) return
  await saveNoteContent(editingSubjectId.value, editingContent.value)
  cancelEditCard()
}
/**
 * 删除某个科目的作业备注。
 * @param subjectId 科目 ID
 * @returns 无返回值
 */
async function deleteCardNote(subjectId: string) {
  await saveNoteContent(subjectId, '')
}

const subjectDialogVisible = ref(false)

/**
 * 将日期对象格式化为 YYYY-MM-DD 字符串，作为作业记录的 record_date。
 * @param date 待格式化的日期
 * @returns 形如 2026-09-16 的日期字符串
 */
function formatDate(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const dayOfMonth = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${dayOfMonth}`
}

/**
 * 生成「学生 + 科目」单元格的唯一键，用于作业记录 Map 的读写。
 * @param studentId 学生 ID
 * @param subjectId 科目 ID
 * @returns 由学生 ID 与科目 ID 拼接而成的键
 */
function recordKey(studentId: string, subjectId: string): string {
  return `${studentId}__${subjectId}`
}

const filteredStudents = computed(() => {
  let studentRows = allStudentList.value
  const keyword = searchKeyword.value.trim()
  if (keyword) {
    studentRows = studentRows.filter(
      (studentRow) => (studentRow.student_name || studentRow.name || '').includes(keyword),
    )
  }
  if (showIncompleteOnly.value) {
    // 只保留：在当前筛选学科中存在未完成记录的学生
    studentRows = studentRows.filter((studentRow) => {
      const targetSubjects = filterSubjectId.value
        ? subjectList.value.filter((subjectRow) => subjectRow.id === filterSubjectId.value)
        : subjectList.value
      return targetSubjects.some((subjectRow) => {
        const homeworkRecord = recordMap.value.get(recordKey(studentRow.id, subjectRow.id))
        return !homeworkRecord || !homeworkRecord.is_done
      })
    })
  }
  return studentRows
})

const filteredSubjects = computed(() => {
  if (!filterSubjectId.value) return subjectList.value
  return subjectList.value.filter((subjectRow) => subjectRow.id === filterSubjectId.value)
})

const totalCells = computed(() => filteredStudents.value.length * filteredSubjects.value.length)
const doneCells = computed(() => {
  let doneCount = 0
  filteredStudents.value.forEach((studentRow) => {
    filteredSubjects.value.forEach((subjectRow) => {
      const homeworkRecord = recordMap.value.get(recordKey(studentRow.id, subjectRow.id))
      if (homeworkRecord && homeworkRecord.is_done) doneCount++
    })
  })
  return doneCount
})
const completionRate = computed(() => {
  if (totalCells.value === 0) return 0
  return Math.round((doneCells.value / totalCells.value) * 100)
})

/**
 * 加载本校配置的作业科目（按 sort_order 升序）。
 * @returns 无返回值（副作用：写入 subjectList）
 */
async function loadSubjects() {
  if (!userStore.schoolId) return
  try {
    const { data: subjectRows, error } = await supabase
      .from('homework_subjects')
      .select('id, subject_name, sort_order')
      .eq('school_id', userStore.schoolId)
      .order('sort_order', { ascending: true })
    if (error) throw error
    subjectList.value = (subjectRows ?? []) as SubjectRow[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载科目列表失败')
  }
}

/**
 * 加载作业看板需要的学生列表。
 * 学校管理员按所选班级（未选则按学校）取数；教师固定取自己任教的班级。
 * @returns 无返回值（副作用：写入 allStudentList）
 */
async function loadStudents() {
  if (!userStore.schoolId) return
  try {
    let query = supabase
      .from('students')
      .select('id, student_name, student_no, class_id')
      .order('student_name', { ascending: true })
    if (userStore.role === 'school_admin') {
      if (filterClassId.value) {
        query = query.eq('class_id', filterClassId.value)
      } else {
        query = query.eq('school_id', userStore.schoolId)
      }
    } else {
      // 教师：按当前操作班级取学生（可切到本校任意班）
      if (!effectiveClassId.value) return
      query = query.eq('class_id', effectiveClassId.value)
    }
    const { data: studentRows, error } = await query
    if (error) throw error
    allStudentList.value = (studentRows ?? []) as StudentRow[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载学生列表失败')
  }
}

/**
 * 加载所选日期下、当前学生范围内的作业完成记录，并整理为「学生+科目」索引的 Map。
 * @returns 无返回值（副作用：写入 recordMap）
 */
async function loadRecords() {
  if (subjectList.value.length === 0 || allStudentList.value.length === 0) {
    recordMap.value = new Map()
    return
  }
  try {
    const studentIds = allStudentList.value.map((studentRow) => studentRow.id)
    const { data: recordRows, error } = await supabase
      .from('homework_records')
      .select('id, student_id, subject_id, is_done')
      .eq('record_date', selectedDate.value)
      .in('student_id', studentIds)
    if (error) throw error
    const loadedRecordMap = new Map<string, RecordRow>()
    ;(recordRows ?? []).forEach((recordRow: any) => {
      loadedRecordMap.set(recordKey(recordRow.student_id, recordRow.subject_id), recordRow as RecordRow)
    })
    recordMap.value = loadedRecordMap
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载作业记录失败')
  }
}

/**
 * 切换某个学生在某科目上的完成状态：没有记录时新增一条并记为已完成，
 * 已有记录时把 is_done 取反后更新。
 * @param studentId 学生 ID
 * @param subjectId 科目 ID
 * @returns 无返回值；成功后同步更新本地 recordMap
 */
async function toggleRecord(studentId: string, subjectId: string) {
  if (!userStore.schoolId || !userStore.id) return
  const cellKey = recordKey(studentId, subjectId)
  const existingRecord = recordMap.value.get(cellKey)
  const now = new Date().toISOString()

  const studentClassId = allStudentList.value.find((studentRow) => studentRow.id === studentId)?.class_id || effectiveClassId.value || undefined

  try {
    if (existingRecord) {
      const newDone = !existingRecord.is_done
      const { error } = await supabase
        .from('homework_records')
        .update({
          is_done: newDone,
          update_user_id: userStore.id,
          update_time: now,
        })
        .eq('id', existingRecord.id)
      if (error) throw error
      const updated = { ...existingRecord, is_done: newDone }
      recordMap.value.set(cellKey, updated)
    } else {
      const { data: insertedRows, error } = await supabase
        .from('homework_records')
        .insert({
          school_id: userStore.schoolId,
          class_id: studentClassId,
          student_id: studentId,
          subject_id: subjectId,
          record_date: selectedDate.value,
          is_done: true,
          update_user_id: userStore.id,
          update_time: now,
        })
        .select()
      if (error) throw error
      const insertedRow = (insertedRows ?? [])[0] as RecordRow | undefined
      if (insertedRow) {
        recordMap.value.set(cellKey, insertedRow)
      }
    }
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '更新作业状态失败')
  }
}

/**
 * 计算某个单元格的展示状态。
 * @param studentId 学生 ID
 * @param subjectId 科目 ID
 * @returns done=已完成，pending=已登记未完成，none=当天无记录
 */
function getCellStatus(studentId: string, subjectId: string): 'done' | 'pending' | 'none' {
  const homeworkRecord = recordMap.value.get(recordKey(studentId, subjectId))
  if (!homeworkRecord) return 'none'
  return homeworkRecord.is_done ? 'done' : 'pending'
}

/**
 * 加载当前班级在所选日期下的作业内容备注。
 * @returns 无返回值（副作用：写入 noteList）
 */
async function loadNotes() {
  if (!effectiveClassId.value) return
  try {
    const { data: noteRows, error } = await supabase
      .from('homework_notes')
      .select('id, subject_id, subject_name, content')
      .eq('class_id', effectiveClassId.value)
      .eq('record_date', selectedDate.value)
    if (error) throw error
    noteList.value = (noteRows ?? []) as NoteRow[]
    syncNoteDraft()
  } catch (err: unknown) {
    // 读取失败会让"备注墙"空白，这里必须让用户看见原因，不能静默吞掉
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载作业备注失败')
  }
}

/**
 * 保存某个科目当天的作业内容：已有备注则更新，内容为空则删除，不存在则新增。
 * @param subjectId 科目 ID
 * @param content 作业内容文本
 * @returns 无返回值；成功后重新加载备注并提示
 */
async function saveNoteContent(subjectId: string, content: string) {
  const classId = effectiveClassId.value
  if (!classId) {
    // 学校管理员未选班级时无法定位作业归属，直接说清原因，避免"点了没反应"
    ElMessage.warning('请先在上方选择班级')
    return
  }
  const subjectName = subjectList.value.find((subjectRow) => subjectRow.id === subjectId)?.subject_name
  const existingNote = noteList.value.find((noteItem) => noteItem.subject_id === subjectId)
  const trimmedContent = content.trim()
  // 与已保存内容一致：不发请求、也不提示，避免一失焦就弹"备注已保存"
  if ((existingNote?.content ?? '') === trimmedContent) return
  try {
    if (existingNote) {
      if (!trimmedContent) {
        // 清空已有备注等价于删除
        const { error } = await supabase.from('homework_notes').delete().eq('id', existingNote.id)
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('homework_notes')
          .update({ content: trimmedContent })
          .eq('id', existingNote.id)
        if (error) throw error
      }
    } else {
      // 原本就没有备注且内容为空：无内容可落库，静默结束，不再谎报"已保存"
      if (!trimmedContent) return
      const { error } = await supabase.from('homework_notes').insert({
        school_id: userStore.schoolId,
        class_id: classId,
        record_date: selectedDate.value,
        subject_id: subjectId,
        subject_name: subjectName,
        content: trimmedContent,
      })
      if (error) throw error
    }
    await loadNotes()
    ElMessage.success('备注已保存')
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存备注失败')
  }
}

/**
 * 看板初始化入口：并行加载科目、学生、备注，再按依赖顺序加载作业记录。
 * @returns 无返回值（副作用：维护 boardLoading 状态，并写入各列表数据）
 */
async function loadAll() {
  boardLoading.value = true
  try {
    await Promise.all([loadSubjects(), loadStudents(), loadNotes()])
    await loadRecords()
    if (!effectiveClassId.value) {
      noteList.value = []
    }
    // loadNotes 可能与 loadSubjects 并行完成，科目列表后到时需再同步一次草稿
    syncNoteDraft()
  } finally {
    boardLoading.value = false
  }
}

watch(selectedDate, () => {
  loadRecords()
  loadNotes()
})

watch(filterClassId, () => {
  loadAll()
})

onMounted(async () => {
  await loadSchoolClasses()
  await loadAll()
})
</script>

<template>
  <el-card>
    <template #header>
      <div class="toolbar">
        <div class="toolbar-left">
          <el-date-picker
            v-model="selectedDate"
            type="date"
            value-format="YYYY-MM-DD"
            placeholder="选择日期"
            :icon="Calendar"
            style="width: 180px"
          />
          <el-input
            v-model="searchKeyword"
            placeholder="搜索学生姓名"
            clearable
            style="width: 200px"
          />
          <el-select
            v-model="filterSubjectId"
            placeholder="全部学科"
            clearable
            style="width: 160px"
          >
            <el-option
              v-for="subjectItem in subjectList"
              :key="subjectItem.id"
              :label="subjectItem.subject_name || subjectItem.name"
              :value="subjectItem.id"
            />
          </el-select>
          <el-switch
            v-model="showIncompleteOnly"
            active-text="只看未完成"
          />
        </div>
        <div class="toolbar-center">
          <el-tag :type="completionRate >= 80 ? 'success' : completionRate >= 50 ? 'warning' : 'danger'" effect="light" size="large">
            今日完成：{{ doneCells }} / {{ totalCells }}（{{ completionRate }}%）
          </el-tag>
        </div>
        <div class="toolbar-right">
          <el-select
            v-if="schoolClasses.length > 0"
            v-model="filterClassId"
            :clearable="userStore.role === 'school_admin'"
            :placeholder="userStore.role === 'school_admin' ? '按班级筛选' : '切换班级'"
            style="width: 190px"
            size="small"
          >
            <el-option v-if="userStore.role === 'school_admin'" label="全部班级" value="" />
            <el-option
              v-for="classOption in schoolClasses"
              :key="classOption.id"
              :label="classOption.class_name"
              :value="classOption.id"
            />
          </el-select>
          <el-button :icon="Setting" @click="subjectDialogVisible = true">科目管理</el-button>
        </div>
      </div>
    </template>

    <!-- 今日作业内容 -->
    <div class="notes-section">
      <!-- 第一层：快捷输入条 -->
      <div class="quick-input-row">
        <span class="quick-label">📝 快速录入：</span>
        <div
          v-for="subjectItem in subjectList"
          :key="subjectItem.id"
          class="quick-item"
        >
          <span class="quick-subject">{{ subjectItem.subject_name || subjectItem.name }}</span>
          <el-input
            v-model="noteDraft[subjectItem.id]"
            class="quick-input"
            placeholder="作业内容…"
            size="small"
            clearable
            @blur="saveNoteContent(subjectItem.id, noteDraft[subjectItem.id] ?? '')"
            @keyup.enter="saveNoteContent(subjectItem.id, noteDraft[subjectItem.id] ?? '')"
          />
        </div>
      </div>

      <!-- 第二层：卡片展示（晚自习作业墙） -->
      <div class="card-wall" v-if="noteList.length > 0">
        <div
          v-for="subjectItem in subjectList"
          :key="subjectItem.id"
          class="hw-card"
        >
          <div
            v-if="noteList.find((noteItem) => noteItem.subject_id === subjectItem.id)"
            class="hw-card-inner"
          >
            <div class="hw-card-header">
              <span
                class="hw-subject-badge"
                :style="{ background: subjectColor(subjectItem.id) }"
              >
                {{ subjectItem.subject_name || subjectItem.name }}
              </span>
              <div class="hw-card-actions">
                <el-tooltip content="编辑" placement="top">
                  <el-button link size="small" @click="startEditCard(subjectItem)">✏️</el-button>
                </el-tooltip>
                <el-tooltip content="删除" placement="top">
                  <el-button link size="small" @click="deleteCardNote(subjectItem.id)">🗑️</el-button>
                </el-tooltip>
              </div>
            </div>
            <div
              v-if="editingSubjectId !== subjectItem.id"
              class="hw-card-body"
              :style="{ whiteSpace: 'pre-wrap' }"
            >{{ noteList.find((noteItem) => noteItem.subject_id === subjectItem.id)?.content }}</div>
            <div v-else class="hw-card-edit">
              <el-input
                v-model="editingContent"
                type="textarea"
                :rows="4"
                placeholder="填写详细作业内容…"
                autosize
              />
              <div class="hw-card-edit-actions">
                <el-button size="small" @click="cancelEditCard">取消</el-button>
                <el-button size="small" type="primary" @click="confirmEditCard">保存</el-button>
              </div>
            </div>
          </div>
          <div v-else class="hw-card hw-card-empty">
            <div class="hw-card-inner" style="opacity: 0.45">
              <div class="hw-card-header">
                <span class="hw-subject-badge" :style="{ background: subjectColor(subjectItem.id) }">
                  {{ subjectItem.subject_name || subjectItem.name }}
                </span>
              </div>
              <div class="hw-card-body hw-card-body-empty">未布置作业</div>
            </div>
          </div>
        </div>
      </div>
      <div v-else class="notes-empty-banner">
        📢 今日尚未布置任何作业 — 在上方快捷输入条填写学科作业内容，即可生成下方作业卡片墙
      </div>
    </div>

    <el-table :data="filteredStudents" v-loading="boardLoading" border stripe style="width: 100%">
      <el-table-column label="学生姓名" width="140" fixed="left">
        <template #default="{ row: studentRow }">
          {{ studentRow.student_name || studentRow.name }}
        </template>
      </el-table-column>
      <el-table-column
        v-for="subjectItem in filteredSubjects"
        :key="subjectItem.id"
        :label="subjectItem.subject_name || subjectItem.name"
        min-width="100"
        align="center"
      >
        <template #default="{ row: studentRow }">
          <button
            class="status-cell"
            :class="`status-${getCellStatus(studentRow.id, subjectItem.id)}`"
            :title="`${studentRow.student_name || studentRow.name} - ${subjectItem.subject_name}`"
            @click="toggleRecord(studentRow.id, subjectItem.id)"
          >
            <span v-if="getCellStatus(studentRow.id, subjectItem.id) === 'done'">✅</span>
            <span v-else-if="getCellStatus(studentRow.id, subjectItem.id) === 'pending'">⬜</span>
            <span v-else>◯</span>
          </button>
        </template>
      </el-table-column>
    </el-table>

    <SubjectManageDialog
      v-model:visible="subjectDialogVisible"
      @refresh="loadSubjects"
    />
  </el-card>
</template>

<style scoped>
.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
  flex-wrap: wrap;
}
.toolbar-left,
.toolbar-right {
  display: flex;
  align-items: center;
  gap: 12px;
}
.toolbar-center {
  flex: 1;
  display: flex;
  justify-content: center;
}
.status-cell {
  width: 36px;
  height: 36px;
  border: none;
  background: transparent;
  cursor: pointer;
  font-size: 20px;
  border-radius: 6px;
  transition: background-color 0.15s;
}
.status-cell:hover {
  background-color: var(--el-fill-color-light);
}

/* 今日作业 — 快速录入 + 卡片墙 */
.notes-section {
  margin: 12px 0;
}

/* 快速录入条 */
.quick-input-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px 16px;
  padding: 12px 16px;
  background: linear-gradient(135deg, #f8faff 0%, #f0f4ff 100%);
  border: 1px dashed #c7d4ff;
  border-radius: 10px;
  margin-bottom: 12px;
}
.quick-label {
  font-size: 14px;
  font-weight: 600;
  color: #2b5ce6;
  flex-shrink: 0;
}
.quick-item {
  display: flex;
  align-items: center;
  gap: 6px;
}
.quick-subject {
  flex-shrink: 0;
  font-size: 13px;
  font-weight: 500;
  color: #374151;
  min-width: 32px;
}
.quick-input { width: 200px; }
@media (max-width: 600px) { .quick-input { width: 140px; } }

/* 卡片墙 */
.card-wall {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 14px;
}
.hw-card {
  background: transparent;
}
.hw-card-inner {
  background: #FFFFFF;
  border: 1px solid #E5E9F0;
  border-radius: 14px;
  padding: 16px;
  box-shadow: 0 2px 10px rgba(30, 58, 138, 0.06);
  transition: transform 0.15s, box-shadow 0.15s;
  height: 100%;
  display: flex;
  flex-direction: column;
}
.hw-card:hover .hw-card-inner {
  transform: translateY(-2px);
  box-shadow: 0 6px 20px rgba(30, 58, 138, 0.12);
}
.hw-card-empty .hw-card-inner {
  border-style: dashed;
  background: #FAFBFF;
}

.hw-card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 10px;
}
.hw-subject-badge {
  display: inline-flex;
  align-items: center;
  padding: 4px 12px;
  border-radius: 20px;
  color: #fff;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 1px;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.1);
}
.hw-card-actions {
  display: flex;
  gap: 2px;
  opacity: 0.4;
  transition: opacity 0.15s;
}
.hw-card:hover .hw-card-actions { opacity: 1; }

.hw-card-body {
  flex: 1;
  font-size: 14px;
  line-height: 1.75;
  color: #1F2937;
  font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
  word-break: break-word;
}
.hw-card-body-empty {
  color: #9CA3AF;
  font-style: italic;
  text-align: center;
  padding: 20px 0;
  font-size: 13px;
}

.hw-card-edit {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.hw-card-edit-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}

.notes-empty-banner {
  padding: 24px 16px;
  text-align: center;
  font-size: 13px;
  color: #6B7280;
  background: #F3F4F6;
  border-radius: 10px;
  border: 1px dashed #D1D5DB;
}
</style>
