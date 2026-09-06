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
const loading = ref(false)
const subjects = ref<SubjectRow[]>([])
const allStudents = ref<StudentRow[]>([])
const records = ref<Map<string, RecordRow>>(new Map())
const notes = ref<NoteRow[]>([])  // 今日作业备注

const filterClassId = ref<string>('')
const schoolClasses = ref<{ id: string; class_name: string }[]>([])

const effectiveClassId = computed<string | null>(() => {
  if (userStore.role === 'school_admin') return filterClassId.value || null
  return userStore.classId || null
})

async function loadSchoolClasses() {
  if (userStore.role !== 'school_admin' || !userStore.schoolId) return
  try {
    const { data, error } = await supabase
      .from('classes')
      .select('id, class_name')
      .eq('school_id', userStore.schoolId)
    if (error) throw error
    schoolClasses.value = (data ?? []) as { id: string; class_name: string }[]
  } catch (err: any) {
    ElMessage.error(err.message || '加载班级列表失败')
  }
}

// 卡片编辑状态
const editingSubjectId = ref<string | null>(null)
const editingContent = ref('')

// 学科配色（柔和渐变底）
function subjectColor(id: string): string {
  const sub = subjects.value.find((s) => s.id === id)
  if (!sub) return '#2B5CE6'
  // 给每个学科按其名字生成稳定颜色
  const palette = ['#2B5CE6', '#10B981', '#F59E0B', '#EF4444', '#8B5CF6', '#06B6D4', '#EC4899']
  let h = 0
  for (let i = 0; i < sub.subject_name.length; i++) h += sub.subject_name.charCodeAt(i)
  return palette[h % palette.length]
}

function startEditCard(sub: SubjectRow) {
  editingSubjectId.value = sub.id
  editingContent.value = notes.value.find((n) => n.subject_id === sub.id)?.content || ''
}
function cancelEditCard() {
  editingSubjectId.value = null
  editingContent.value = ''
}
async function confirmEditCard() {
  if (!editingSubjectId.value) return
  await saveNoteContent(editingSubjectId.value, editingContent.value)
  cancelEditCard()
}
async function deleteCardNote(subjectId: string) {
  await saveNoteContent(subjectId, '')
}

const subjectDialogVisible = ref(false)

function formatDate(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function recordKey(studentId: string, subjectId: string): string {
  return `${studentId}__${subjectId}`
}

const filteredStudents = computed(() => {
  let list = allStudents.value
  const kw = searchKeyword.value.trim()
  if (kw) {
    list = list.filter(
      (s) => (s.student_name || s.name || '').includes(kw),
    )
  }
  if (showIncompleteOnly.value) {
    // 只保留：在当前筛选学科中存在未完成记录的学生
    list = list.filter((s) => {
      const targetSubjects = filterSubjectId.value
        ? subjects.value.filter((sub) => sub.id === filterSubjectId.value)
        : subjects.value
      return targetSubjects.some((sub) => {
        const rec = records.value.get(recordKey(s.id, sub.id))
        return !rec || !rec.is_done
      })
    })
  }
  return list
})

const filteredSubjects = computed(() => {
  if (!filterSubjectId.value) return subjects.value
  return subjects.value.filter((s) => s.id === filterSubjectId.value)
})

const totalCells = computed(() => filteredStudents.value.length * filteredSubjects.value.length)
const doneCells = computed(() => {
  let n = 0
  filteredStudents.value.forEach((s) => {
    filteredSubjects.value.forEach((sub) => {
      const rec = records.value.get(recordKey(s.id, sub.id))
      if (rec && rec.is_done) n++
    })
  })
  return n
})
const completionRate = computed(() => {
  if (totalCells.value === 0) return 0
  return Math.round((doneCells.value / totalCells.value) * 100)
})

async function loadSubjects() {
  if (!userStore.schoolId) return
  try {
    const { data, error } = await supabase
      .from('homework_subjects')
      .select('id, subject_name, sort_order')
      .eq('school_id', userStore.schoolId)
      .order('sort_order', { ascending: true })
    if (error) throw error
    subjects.value = (data ?? []) as SubjectRow[]
  } catch (err: any) {
    ElMessage.error(err.message || '加载科目列表失败')
  }
}

async function loadStudents() {
  if (userStore.role !== 'school_admin' && !userStore.classId) return
  if (userStore.role === 'school_admin' && !userStore.schoolId) return
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
      query = query.eq('class_id', userStore.classId)
    }
    const { data, error } = await query
    if (error) throw error
    allStudents.value = (data ?? []) as StudentRow[]
  } catch (err: any) {
    ElMessage.error(err.message || '加载学生列表失败')
  }
}

async function loadRecords() {
  if (subjects.value.length === 0 || allStudents.value.length === 0) {
    records.value = new Map()
    return
  }
  try {
    const studentIds = allStudents.value.map((s) => s.id)
    const { data, error } = await supabase
      .from('homework_records')
      .select('id, student_id, subject_id, is_done')
      .eq('record_date', selectedDate.value)
      .in('student_id', studentIds)
    if (error) throw error
    const map = new Map<string, RecordRow>()
    ;(data ?? []).forEach((r: any) => {
      map.set(recordKey(r.student_id, r.subject_id), r as RecordRow)
    })
    records.value = map
  } catch (err: any) {
    ElMessage.error(err.message || '加载作业记录失败')
  }
}

async function toggleRecord(studentId: string, subjectId: string) {
  if (!userStore.schoolId || !userStore.id) return
  const key = recordKey(studentId, subjectId)
  const existing = records.value.get(key)
  const now = new Date().toISOString()

  const studentClassId = allStudents.value.find((s) => s.id === studentId)?.class_id || effectiveClassId.value || undefined

  try {
    if (existing) {
      const newDone = !existing.is_done
      const { error } = await supabase
        .from('homework_records')
        .update({
          is_done: newDone,
          update_user_id: userStore.id,
          update_time: now,
        })
        .eq('id', existing.id)
      if (error) throw error
      const updated = { ...existing, is_done: newDone }
      records.value.set(key, updated)
    } else {
      const { data, error } = await supabase
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
      const row = (data ?? [])[0] as RecordRow | undefined
      if (row) {
        records.value.set(key, row)
      }
    }
  } catch (err: any) {
    ElMessage.error(err.message || '更新作业状态失败')
  }
}

function getCellStatus(studentId: string, subjectId: string): 'done' | 'pending' | 'none' {
  const rec = records.value.get(recordKey(studentId, subjectId))
  if (!rec) return 'none'
  return rec.is_done ? 'done' : 'pending'
}

async function loadNotes() {
  if (!effectiveClassId.value) return
  try {
    const { data, error } = await supabase
      .from('homework_notes')
      .select('id, subject_id, subject_name, content')
      .eq('class_id', effectiveClassId.value)
      .eq('record_date', selectedDate.value)
    if (error) throw error
    notes.value = (data ?? []) as NoteRow[]
  } catch (err: any) {
    // 表可能不存在，静默
  }
}

async function saveNoteContent(subjectId: string, content: string) {
  const classId = effectiveClassId.value
  if (!classId) return
  const subjectName = subjects.value.find((s) => s.id === subjectId)?.subject_name
  const existing = notes.value.find((n) => n.subject_id === subjectId)
  const trimmed = content.trim()
  try {
    if (existing) {
      if (!trimmed) {
        // 删除空内容
        const { error } = await supabase.from('homework_notes').delete().eq('id', existing.id)
        if (error) throw error
      } else {
        const { error } = await supabase
          .from('homework_notes')
          .update({ content: trimmed })
          .eq('id', existing.id)
        if (error) throw error
      }
    } else if (trimmed) {
      const { error } = await supabase.from('homework_notes').insert({
        school_id: userStore.schoolId,
        class_id: classId,
        record_date: selectedDate.value,
        subject_id: subjectId,
        subject_name: subjectName,
        content: trimmed,
      })
      if (error) throw error
    }
    await loadNotes()
    ElMessage.success('备注已保存')
  } catch (err: any) {
    ElMessage.error(err.message || '保存备注失败')
  }
}

async function loadAll() {
  loading.value = true
  try {
    await Promise.all([loadSubjects(), loadStudents(), loadNotes()])
    await loadRecords()
    if (!effectiveClassId.value) {
      notes.value = []
    }
  } finally {
    loading.value = false
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
              v-for="sub in subjects"
              :key="sub.id"
              :label="sub.subject_name || sub.name"
              :value="sub.id"
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
            v-if="userStore.role === 'school_admin'"
            v-model="filterClassId"
            clearable
            placeholder="按班级筛选"
            style="width: 180px"
            size="small"
          >
            <el-option label="全部班级" value="" />
            <el-option
              v-for="c in schoolClasses"
              :key="c.id"
              :label="c.class_name"
              :value="c.id"
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
          v-for="sub in subjects"
          :key="sub.id"
          class="quick-item"
        >
          <span class="quick-subject">{{ sub.subject_name || sub.name }}</span>
          <el-input
            class="quick-input"
            :model-value="notes.find((n) => n.subject_id === sub.id)?.content || ''"
            placeholder="作业内容…"
            size="small"
            clearable
            @blur="(e: FocusEvent) => saveNoteContent(sub.id, (e.target as HTMLInputElement).value)"
            @keyup.enter="(e: KeyboardEvent) => saveNoteContent(sub.id, (e.target as HTMLInputElement).value)"
          />
        </div>
      </div>

      <!-- 第二层：卡片展示（晚自习作业墙） -->
      <div class="card-wall" v-if="notes.length > 0">
        <div
          v-for="sub in subjects"
          :key="sub.id"
          class="hw-card"
        >
          <div
            v-if="notes.find((n) => n.subject_id === sub.id)"
            class="hw-card-inner"
          >
            <div class="hw-card-header">
              <span
                class="hw-subject-badge"
                :style="{ background: subjectColor(sub.id) }"
              >
                {{ sub.subject_name || sub.name }}
              </span>
              <div class="hw-card-actions">
                <el-tooltip content="编辑" placement="top">
                  <el-button link size="small" @click="startEditCard(sub)">✏️</el-button>
                </el-tooltip>
                <el-tooltip content="删除" placement="top">
                  <el-button link size="small" @click="deleteCardNote(sub.id)">🗑️</el-button>
                </el-tooltip>
              </div>
            </div>
            <div
              v-if="editingSubjectId !== sub.id"
              class="hw-card-body"
              :style="{ whiteSpace: 'pre-wrap' }"
            >{{ notes.find((n) => n.subject_id === sub.id)?.content }}</div>
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
                <span class="hw-subject-badge" :style="{ background: subjectColor(sub.id) }">
                  {{ sub.subject_name || sub.name }}
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

    <el-table :data="filteredStudents" v-loading="loading" border stripe style="width: 100%">
      <el-table-column label="学生姓名" width="140" fixed="left">
        <template #default="{ row }">
          {{ row.student_name || row.name }}
        </template>
      </el-table-column>
      <el-table-column
        v-for="sub in filteredSubjects"
        :key="sub.id"
        :label="sub.subject_name || sub.name"
        min-width="100"
        align="center"
      >
        <template #default="{ row }">
          <button
            class="status-cell"
            :class="`status-${getCellStatus(row.id, sub.id)}`"
            :title="`${row.student_name || row.name} - ${sub.subject_name}`"
            @click="toggleRecord(row.id, sub.id)"
          >
            <span v-if="getCellStatus(row.id, sub.id) === 'done'">✅</span>
            <span v-else-if="getCellStatus(row.id, sub.id) === 'pending'">⬜</span>
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
