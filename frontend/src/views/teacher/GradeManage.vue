<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Edit, Delete, Upload, Download, Document } from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'
import { exportToExcel } from '@/utils/excel'
import * as XLSX from 'xlsx'

const userStore = useUserStore()

// ===== 分数阈值配置（localStorage，老师可自设） =====
// 两种模式：percent（百分比 0-1）/ score（绝对分数，如 85 表示满分 100 时的 85 分）
const LINE_MODE_KEY = 'MOCK_LINE_MODE'
const EXCELLENT_LINE_KEY = 'MOCK_EXCELLENT_LINE'
const PASS_LINE_KEY = 'MOCK_PASS_LINE'
const lineMode = ref<'percent' | 'score'>(localStorage.getItem(LINE_MODE_KEY) === 'score' ? 'score' : 'percent')
const defaultExcellent = lineMode.value === 'score' ? 85 : 0.85
const defaultPass = lineMode.value === 'score' ? 60 : 0.60
const excellentLine = ref(parseFloat(localStorage.getItem(EXCELLENT_LINE_KEY) || String(defaultExcellent)) || defaultExcellent)
const passLine = ref(parseFloat(localStorage.getItem(PASS_LINE_KEY) || String(defaultPass)) || defaultPass)
// 切换模式时自动转换值
watch(lineMode, (newMode, oldMode) => {
  if (newMode === oldMode) return
  if (oldMode === 'percent' && newMode === 'score') {
    excellentLine.value = Math.round(excellentLine.value * 100)
    passLine.value = Math.round(passLine.value * 100)
  } else if (oldMode === 'score' && newMode === 'percent') {
    excellentLine.value = +(excellentLine.value / 100).toFixed(2)
    passLine.value = +(passLine.value / 100).toFixed(2)
  }
})
// 统一转换：不管模式是什么，都算出百分比
function toPct(lineVal: number, fullScore: number): number {
  if (lineMode.value === 'percent') return lineVal
  return fullScore > 0 ? lineVal / fullScore : 0
}
function saveLine() {
  localStorage.setItem(LINE_MODE_KEY, lineMode.value)
  localStorage.setItem(EXCELLENT_LINE_KEY, String(excellentLine.value))
  localStorage.setItem(PASS_LINE_KEY, String(passLine.value))
  ElMessage.success('分数线已保存')
}

interface StudentOpt {
  id: string
  student_name: string
}

interface ScoreRow {
  id: string
  student_id: string
  student_name?: string
  subject: string
  exam_name: string
  exam_date: string
  score: number
  full_score: number
}

interface MatrixCell {
  id?: string
  score: number | null
  full_score: number
}
interface MatrixRow {
  student_id: string
  student_name: string
  cells: Record<string, MatrixCell>
  total: number
  avg: number
  scoreCount: number
}

const students = ref<StudentOpt[]>([])
const allScores = ref<ScoreRow[]>([])
const loading = ref(false)

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

const examOptions = ref<{ name: string; date: string }[]>([])
const currentExam = ref('')
const currentExamDate = ref('')

const subjectColumns = computed(() => {
  if (!currentExam.value) return []
  const set = new Set<string>()
  allScores.value
    .filter((s) => s.exam_name === currentExam.value)
    .forEach((s) => set.add(s.subject))
  return Array.from(set).sort()
})

const matrixRows = computed<MatrixRow[]>(() => {
  if (!currentExam.value) return []
  const examScores = allScores.value.filter((s) => s.exam_name === currentExam.value)
  const scoreMap = new Map<string, ScoreRow>()
  examScores.forEach((s) => scoreMap.set(`${s.student_id}|${s.subject}`, s))
  const cols = subjectColumns.value
  return students.value.map((stu) => {
    const cells: Record<string, MatrixCell> = {}
    let total = 0
    let scoreCount = 0
    cols.forEach((subj) => {
      const s = scoreMap.get(`${stu.id}|${subj}`)
      if (s) {
        cells[subj] = { id: s.id, score: s.score, full_score: s.full_score }
        total += s.score
        scoreCount++
      } else {
        cells[subj] = { score: null, full_score: 100 }
      }
    })
    return {
      student_id: stu.id,
      student_name: stu.student_name,
      cells,
      total,
      avg: scoreCount > 0 ? +(total / scoreCount).toFixed(1) : 0,
      scoreCount,
    }
  })
})

const totalScoreCells = computed(() =>
  matrixRows.value.reduce((s, r) => s + r.scoreCount, 0),
)

const classAvg = computed(() => {
  const rows = matrixRows.value.filter((r) => r.scoreCount > 0)
  if (rows.length === 0) return 0
  const total = rows.reduce((s, r) => s + r.total, 0)
  const count = rows.reduce((s, r) => s + r.scoreCount, 0)
  return count > 0 ? +(total / count).toFixed(1) : 0
})

const passRate = computed(() => {
  let totalCells = 0, passCells = 0
  matrixRows.value.forEach((r) => {
    Object.values(r.cells).forEach((c) => {
      if (c.score !== null) {
        totalCells++
        if (c.score / c.full_score >= 0.6) passCells++
      }
    })
  })
  return totalCells > 0 ? +((passCells / totalCells) * 100).toFixed(1) : 0
})

function getScoreClass(cell: MatrixCell): string {
  if (cell.score === null) return ''
  const pct = cell.score / cell.full_score
  if (pct >= toPct(excellentLine.value, cell.full_score)) return 'cell-good'
  if (pct < toPct(passLine.value, cell.full_score)) return 'cell-fail'
  return ''
}

// ===== 单元格编辑弹窗 =====
const cellDialogVisible = ref(false)
const cellDialogForm = ref({
  student_id: '',
  student_name: '',
  subject: '',
  score: 0,
  full_score: 100,
  score_id: undefined as string | undefined,
})

function openCellEditor(row: MatrixRow, subject: string) {
  const cell = row.cells[subject]
  cellDialogForm.value = {
    student_id: row.student_id,
    student_name: row.student_name,
    subject,
    score: cell.score ?? 0,
    full_score: cell.full_score,
    score_id: cell.id,
  }
  cellDialogVisible.value = true
}

async function handleCellSubmit() {
  if (cellDialogForm.value.score < 0 || cellDialogForm.value.score > cellDialogForm.value.full_score) {
    ElMessage.warning(`分数范围应在 0 ~ ${cellDialogForm.value.full_score} 之间`)
    return
  }
  try {
    const session = (await supabase.auth.getSession()).data.session
    const operatorId = session?.user.id
    const examDate = currentExamDate.value || new Date().toISOString().slice(0, 10)
    if (cellDialogForm.value.score_id) {
      const { error } = await supabase
        .from('student_scores')
        .update({ score: cellDialogForm.value.score, full_score: cellDialogForm.value.full_score })
        .eq('id', cellDialogForm.value.score_id)
      if (error) throw error
      ElMessage.success('更新成功')
    } else {
      const studentName = students.value.find((s) => s.id === cellDialogForm.value.student_id)?.student_name
      const { error } = await supabase.from('student_scores').insert({
        student_id: cellDialogForm.value.student_id,
        student_name: studentName,
        subject: cellDialogForm.value.subject,
        exam_name: currentExam.value,
        exam_date: examDate,
        score: cellDialogForm.value.score,
        full_score: cellDialogForm.value.full_score,
        school_id: userStore.schoolId,
        class_id: effectiveClassId.value,
        operator_user_id: operatorId,
      })
      if (error) throw error
      ElMessage.success('录入成功')
    }
    cellDialogVisible.value = false
    await loadAll()
  } catch (err: any) {
    ElMessage.error(err.message || '保存失败')
  }
}

async function handleCellDelete() {
  if (!cellDialogForm.value.score_id) {
    ElMessage.warning('该单元格尚无成绩记录')
    return
  }
  try {
    await ElMessageBox.confirm('确定删除该条成绩吗？', '提示', { type: 'warning' })
  } catch {
    return
  }
  try {
    const { error } = await supabase
      .from('student_scores')
      .delete()
      .eq('id', cellDialogForm.value.score_id)
    if (error) throw error
    ElMessage.success('删除成功')
    cellDialogVisible.value = false
    await loadAll()
  } catch (err: any) {
    ElMessage.error(err.message || '删除失败')
  }
}

// ===== 新增考试 =====
const newExamVisible = ref(false)
const newExamForm = ref({ name: '', date: new Date().toISOString().slice(0, 10) })

function openNewExam() {
  newExamForm.value = { name: '', date: new Date().toISOString().slice(0, 10) }
  newExamVisible.value = true
}

function handleNewExam() {
  if (!newExamForm.value.name.trim()) {
    ElMessage.warning('请输入考试名称')
    return
  }
  if (examOptions.value.find((e) => e.name === newExamForm.value.name.trim())) {
    ElMessage.warning('该考试名称已存在')
    return
  }
  const key = 'MOCK_EXAMS'
  const raw = localStorage.getItem(key)
  const list: { name: string; date: string }[] = raw ? JSON.parse(raw) : []
  list.push({ name: newExamForm.value.name.trim(), date: newExamForm.value.date })
  localStorage.setItem(key, JSON.stringify(list))
  examOptions.value = list
  currentExam.value = newExamForm.value.name.trim()
  currentExamDate.value = newExamForm.value.date
  newExamVisible.value = false
  ElMessage.success(`已创建「${currentExam.value}」，可开始录入成绩`)
}

// ===== Excel 导入（宽表格式）=====
function downloadTemplate() {
  const wb = XLSX.utils.book_new()
  const subs = subjectColumns.value.length > 0 ? subjectColumns.value : ['语文', '数学', '英语']
  const examName = currentExam.value || '本次考试'
  const header = ['学生姓名', ...subs]
  const sample1 = ['张三', ...subs.map(() => 85)]
  const sample2 = ['李四', ...subs.map(() => 90)]
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([header, sample1, sample2]), examName)
  XLSX.writeFile(wb, `成绩导入_${examName}.xlsx`)
}

async function handleImport(file: File) {
  if (!currentExam.value) {
    ElMessage.warning('请先选择或创建一个考试')
    return
  }
  const buf = await file.arrayBuffer()
  const wb = XLSX.read(buf, { type: 'array' })
  const sheet = wb.Sheets[wb.SheetNames[0]]
  const rows = XLSX.utils.sheet_to_json(sheet, { header: 1 }) as any[][]
  if (rows.length < 2) {
    ElMessage.warning('模板内容为空')
    return
  }
  const headers = rows[0].map((h) => String(h).trim())
  const headerSubjects = headers.slice(1)

  const records: ScoreRow[] = []
  const session = (await supabase.auth.getSession()).data.session
  const operatorId = session?.user.id

  for (let i = 1; i < rows.length; i++) {
    const row = rows[i]
    if (!row || row.length < 2) continue
    const name = String(row[0] ?? '').trim()
    if (!name) continue
    const student = students.value.find((s) => s.student_name === name)
    if (!student) {
      ElMessage.warning(`第 ${i + 1} 行：未找到学生「${name}」，已跳过`)
      continue
    }
    for (let j = 0; j < headerSubjects.length; j++) {
      const val = row[j + 1]
      if (val === undefined || val === null || val === '') continue
      const score = Number(val)
      if (isNaN(score)) continue
      records.push({
        id: '',
        student_id: student.id,
        student_name: student.student_name,
        subject: headerSubjects[j],
        exam_name: currentExam.value,
        exam_date: currentExamDate.value,
        score,
        full_score: 100,
      })
    }
  }

  if (records.length === 0) {
    ElMessage.warning('没有可导入的有效记录')
    return
  }

  try {
    const { data: existing } = await supabase
      .from('student_scores')
      .select('id')
      .eq('exam_name', currentExam.value)
    const existingIds = (existing ?? []).map((s: any) => s.id)
    if (existingIds.length > 0) {
      await supabase.from('student_scores').delete().in('id', existingIds)
    }
    const { error } = await supabase.from('student_scores').insert(
      records.map((r) => ({
        student_id: r.student_id,
        student_name: r.student_name,
        subject: r.subject,
        exam_name: r.exam_name,
        exam_date: r.exam_date,
        score: r.score,
        full_score: r.full_score,
        school_id: userStore.schoolId,
        class_id: effectiveClassId.value,
        operator_user_id: operatorId,
      })),
    )
    if (error) throw error
    ElMessage.success(`成功导入 ${records.length} 条成绩（已覆盖 ${existingIds.length} 条旧数据）`)
    await loadAll()
  } catch (err: any) {
    ElMessage.error(err.message || '导入失败')
  }
}

function onFileChange(e: Event) {
  const target = e.target as HTMLInputElement
  const file = target.files?.[0]
  if (file) handleImport(file).finally(() => { target.value = '' })
}

function handleExport() {
  if (!currentExam.value || matrixRows.value.length === 0) {
    ElMessage.warning('请先选择有成绩的考试')
    return
  }
  const header = ['学生姓名', ...subjectColumns.value, '总分', '平均分']
  const body = matrixRows.value.map((r) => {
    const scores = subjectColumns.value.map((subj) => {
      const c = r.cells[subj]
      return c.score !== null ? c.score : ''
    })
    return [r.student_name, ...scores, r.total, r.avg]
  })
  exportToExcel([header, ...body], `成绩_${currentExam.value}_${Date.now()}.xlsx`)
}

// ===== 数据加载 =====
async function loadStudents() {
  if (userStore.role !== 'school_admin' && !userStore.classId) return
  if (userStore.role === 'school_admin' && !userStore.schoolId) return
  try {
    let query = supabase
      .from('students')
      .select('id, student_name')
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
    students.value = (data ?? []) as StudentOpt[]
  } catch (err: any) {
    ElMessage.error(err.message || '加载学生列表失败')
  }
}

async function loadAllScores() {
  if (!userStore.schoolId) return
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('student_scores')
      .select('*')
      .order('exam_date', { ascending: true })
      .order('subject', { ascending: true })
    if (error) throw error
    let rows = (data ?? []) as ScoreRow[]
    const stuMap: Record<string, string> = {}
    students.value.forEach((s) => { stuMap[s.id] = s.student_name })
    rows.forEach((r) => { if (!r.student_name) r.student_name = stuMap[r.student_id] })
    allScores.value = rows
  } catch (err: any) {
    ElMessage.error(err.message || '加载成绩失败')
  } finally {
    loading.value = false
  }
}

function loadExamOptions() {
  const stored = localStorage.getItem('MOCK_EXAMS')
  let list: { name: string; date: string }[] = stored ? JSON.parse(stored) : []
  const existing = new Set(list.map((e) => e.name))
  allScores.value.forEach((s) => {
    if (!existing.has(s.exam_name)) {
      list.push({ name: s.exam_name, date: s.exam_date })
      existing.add(s.exam_name)
    }
  })
  list.sort((a, b) => b.date.localeCompare(a.date))
  examOptions.value = list
  if (!currentExam.value && list.length > 0) {
    currentExam.value = list[0].name
    currentExamDate.value = list[0].date
  }
}

async function loadAll() {
  await loadAllScores()
  loadExamOptions()
}

function onExamChange() {
  const e = examOptions.value.find((x) => x.name === currentExam.value)
  currentExamDate.value = e?.date || ''
}
watch(currentExam, onExamChange)

watch(filterClassId, async () => {
  await loadStudents()
})

onMounted(async () => {
  await loadSchoolClasses()
  await loadStudents()
  await loadAll()
})
</script>

<template>
  <div class="grade-manage">
    <div class="exam-bar">
      <div class="exam-left">
        <span class="exam-label">当前考试：</span>
        <el-select v-model="currentExam" placeholder="请选择考试" style="width: 220px" @change="onExamChange">
          <el-option
            v-for="e in examOptions"
            :key="e.name"
            :label="e.name + '（' + (e.date || '无日期') + '）'"
            :value="e.name"
          />
        </el-select>
        <el-button type="primary" :icon="Plus" @click="openNewExam">新增考试</el-button>
        <el-tag v-if="currentExamDate" type="info" effect="plain">
          {{ new Date(currentExamDate).toLocaleDateString('zh-CN') }}
        </el-tag>
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
      </div>
      <div class="exam-right">
        <el-radio-group v-model="lineMode" size="default" style="margin-right: 8px">
          <el-radio-button value="percent">百分比</el-radio-button>
          <el-radio-button value="score">绝对分数</el-radio-button>
        </el-radio-group>
        <span class="cfg-label">优秀线</span>
        <el-input-number
          v-if="lineMode === 'percent'"
          v-model="excellentLine" :min="0.5" :max="1" :step="0.05" :precision="2" size="default" style="width: 100px"
        />
        <el-input-number
          v-else
          v-model="excellentLine" :min="1" :max="150" :step="5" :precision="0" size="default" style="width: 100px"
        />
        <span class="cfg-label">及格线</span>
        <el-input-number
          v-if="lineMode === 'percent'"
          v-model="passLine" :min="0.3" :max="0.8" :step="0.05" :precision="2" size="default" style="width: 100px"
        />
        <el-input-number
          v-else
          v-model="passLine" :min="1" :max="120" :step="5" :precision="0" size="default" style="width: 100px"
        />
        <el-button size="default" @click="saveLine">保存分数线</el-button>
      </div>
    </div>

    <div class="exam-bar" style="margin-top: 8px">
      <div class="exam-left"></div>
      <div class="exam-right">
        <el-button :icon="Document" @click="downloadTemplate">下载模板</el-button>
        <el-button tag="label" for="grade-import" :icon="Upload">批量导入</el-button>
        <input id="grade-import" type="file" accept=".xlsx,.xls" style="display:none" @change="onFileChange" />
        <el-button :icon="Download" @click="handleExport">导出 Excel</el-button>
      </div>
    </div>

    <div v-if="currentExam && matrixRows.length > 0" class="kpi-row">
      <div class="kpi-card mini">
        <div class="kpi-label">参考学生</div>
        <div class="hero-number">{{ matrixRows.length }}</div>
      </div>
      <div class="kpi-card mini">
        <div class="kpi-label">已录入科次</div>
        <div class="hero-number">{{ totalScoreCells }}</div>
      </div>
      <div class="kpi-card mini">
        <div class="kpi-label">班级平均分</div>
        <div class="hero-number">{{ classAvg }}</div>
      </div>
      <div class="kpi-card mini">
        <div class="kpi-label">整体及格率</div>
        <div class="hero-number green">{{ passRate }}%</div>
      </div>
    </div>

    <div class="table-wrap" v-if="currentExam">
      <el-table :data="matrixRows" v-loading="loading" border stripe style="width: 100%">
        <el-table-column prop="student_name" label="学生" width="140" fixed="left">
          <template #default="{ row }">
            <div class="student-cell">
              <div class="student-avatar">{{ (row as MatrixRow).student_name.charAt(0) }}</div>
              <div class="student-name">{{ (row as MatrixRow).student_name }}</div>
            </div>
          </template>
        </el-table-column>

        <el-table-column
          v-for="subj in subjectColumns"
          :key="subj"
          :label="subj"
          :width="110"
          align="center"
        >
          <template #default="{ row }">
            <div class="score-cell" :class="getScoreClass((row as MatrixRow).cells[subj])" @click="openCellEditor(row as MatrixRow, subj)">
              <template v-if="(row as MatrixRow).cells[subj].score !== null">
                <span class="score-num">{{ (row as MatrixRow).cells[subj].score }}</span>
                <span class="score-full">/ {{ (row as MatrixRow).cells[subj].full_score }}</span>
              </template>
              <template v-else>
                <span class="score-empty">+ 录入</span>
              </template>
            </div>
          </template>
        </el-table-column>

        <el-table-column label="总分" width="100" align="center" fixed="right">
          <template #default="{ row }"><span class="score-num total">{{ (row as MatrixRow).total }}</span></template>
        </el-table-column>
        <el-table-column label="平均分" width="100" align="center" fixed="right">
          <template #default="{ row }"><span class="score-num avg">{{ (row as MatrixRow).avg }}</span></template>
        </el-table-column>
      </el-table>
      <el-empty v-if="matrixRows.length === 0 && !loading" description="暂无学生数据" />
    </div>

    <el-empty v-else description="请先选择或创建一个考试" />

    <!-- 单元格编辑弹窗 -->
    <el-dialog
      v-model="cellDialogVisible"
      :title="cellDialogForm.student_name + ' · ' + cellDialogForm.subject"
      width="400px"
      destroy-on-close
    >
      <el-form label-width="80px">
        <el-form-item label="学生"><span>{{ cellDialogForm.student_name }}</span></el-form-item>
        <el-form-item label="学科"><span>{{ cellDialogForm.subject }}</span></el-form-item>
        <el-form-item label="分数" required>
          <el-input-number
            v-model="cellDialogForm.score"
            :min="0"
            :max="cellDialogForm.full_score"
            :step="1"
            style="width: 100%"
          />
        </el-form-item>
        <el-form-item label="满分">
          <el-input-number
            v-model="cellDialogForm.full_score"
            :min="50"
            :max="150"
            :step="10"
            style="width: 100%"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button
          v-if="cellDialogForm.score_id"
          type="danger"
          plain
          :icon="Delete"
          @click="handleCellDelete"
        >删除</el-button>
        <span style="flex: 1" />
        <el-button @click="cellDialogVisible = false">取消</el-button>
        <el-button type="primary" :icon="Edit" @click="handleCellSubmit">保存</el-button>
      </template>
    </el-dialog>

    <!-- 新增考试弹窗 -->
    <el-dialog v-model="newExamVisible" title="新增考试" width="380px" destroy-on-close>
      <el-form label-width="80px">
        <el-form-item label="考试名称" required>
          <el-input v-model="newExamForm.name" placeholder="如：期中考试 / 第三次月考" maxlength="30" />
        </el-form-item>
        <el-form-item label="考试日期">
          <el-date-picker
            v-model="newExamForm.date"
            type="date"
            value-format="YYYY-MM-DD"
            style="width: 100%"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="newExamVisible = false">取消</el-button>
        <el-button type="primary" @click="handleNewExam">创建</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.grade-manage { padding: 0; }

.exam-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: 12px;
  margin-bottom: 16px;
  padding: 14px 20px;
  background: linear-gradient(135deg, #EBF1FE 0%, #F5F7FA 100%);
  border-radius: 12px;
  border: 1px solid #E5E9F0;
}
.exam-left { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.exam-icon { font-size: 20px; color: #2B5CE6; }
.exam-label { font-size: 14px; color: #6B7280; }
.exam-right { display: flex; align-items: center; gap: 8px; }

.kpi-row { display: flex; gap: 12px; margin-bottom: 16px; flex-wrap: wrap; }
.kpi-card.mini { flex: 1; min-width: 160px; padding: 16px 20px; }
.kpi-card.mini .hero-number { font-size: 32px; }

.table-wrap {
  background: #FFFFFF;
  border-radius: 12px;
  border: 1px solid #E5E9F0;
  box-shadow: 0 2px 8px rgba(30, 58, 138, 0.04);
  overflow: hidden;
}

.student-cell { display: flex; align-items: center; gap: 10px; }
.student-avatar {
  width: 32px; height: 32px; border-radius: 50%;
  background: #2B5CE6; color: #fff;
  font-weight: 600; font-size: 14px;
  display: flex; align-items: center; justify-content: center;
  flex-shrink: 0;
}
.student-name { font-weight: 500; color: #1F2937; }

.score-cell {
  display: inline-flex; flex-direction: column;
  align-items: center; gap: 2px;
  cursor: pointer; padding: 6px 8px;
  border-radius: 8px; transition: background 0.15s;
  min-width: 80px;
}
.score-cell:hover { background: #EBF1FE; }
.score-num { font-weight: 700; font-size: 16px; color: #1F2937; font-variant-numeric: tabular-nums; }
.score-num.total { color: #2B5CE6; font-size: 18px; }
.score-num.avg { color: #F59E0B; font-size: 16px; }
.score-full { font-size: 11px; color: #9CA3AF; }
.score-empty { color: #9CA3AF; font-size: 12px; font-weight: 500; }
.score-cell.cell-good .score-num { color: #10B981; }
.score-cell.cell-fail .score-num { color: #EF4444; }
</style>
