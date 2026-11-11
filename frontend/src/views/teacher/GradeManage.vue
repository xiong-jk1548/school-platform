<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Edit, Delete, Upload, Download, Document, Key } from '@element-plus/icons-vue'
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
const schoolClasses = ref<{ id: string; class_name: string; homeroom_teacher_id?: string | null }[]>([])
/** 教师身份下：本人被授权访问成绩的班级 id 列表 */
const grantedClassIds = ref<string[]>([])

/**
 * 当前实际操作的班级。
 * 学校管理员用顶部下拉选择（可为空＝本校全部）；教师用下拉选择，默认回落到自己绑定的班。
 */
const effectiveClassId = computed<string | null>(() => {
  if (userStore.role === 'school_admin') return filterClassId.value || null
  return filterClassId.value || userStore.boundClassId || null
})

/**
 * 当前班级是否由本人担任班主任 —— 决定「成绩授权」按钮是否可用。
 * 与后端 fn_is_homeroom_of 口径保持一致：classes.homeroom_teacher_id 优先；
 * 该字段未维护时（如种子数据）回退到 profiles.class_id（即 store 的 boundClassId）。
 * @returns 是否可管理本班成绩授权
 */
const canGrantForCurrentClass = computed(() => {
  if (userStore.role !== 'teacher' || !effectiveClassId.value) return false
  const currentClass = schoolClasses.value.find((classItem) => classItem.id === effectiveClassId.value)
  if (currentClass?.homeroom_teacher_id) return currentClass.homeroom_teacher_id === userStore.id
  return effectiveClassId.value === userStore.boundClassId
})

/**
 * 加载顶部下拉的班级列表。
 * 学校管理员＝本校全部班级；教师＝本人绑定的班 + 已被班主任授权访问成绩的班。
 * @returns 无返回值（副作用：写入 schoolClasses，教师场景下同时刷新 grantedClassIds）
 */
async function loadSchoolClasses() {
  if (!userStore.schoolId) return
  try {
    if (userStore.role === 'school_admin') {
      const { data: classRows, error } = await supabase
        .from('classes')
        .select('id, class_name, homeroom_teacher_id')
        .eq('school_id', userStore.schoolId)
      if (error) throw error
      schoolClasses.value = (classRows ?? []) as typeof schoolClasses.value
      return
    }
    // 教师：自己绑定的班 + 已获授权的班
    const { data: grantRows, error: grantError } = await supabase
      .from('grade_access_grants')
      .select('class_id')
      .eq('teacher_id', userStore.id)
    if (grantError) throw grantError
    grantedClassIds.value = Array.from(new Set((grantRows ?? []).map((grant: any) => grant.class_id as string)))
    const wantedIds = Array.from(
      new Set([userStore.boundClassId, ...grantedClassIds.value].filter(Boolean) as string[]),
    )
    if (wantedIds.length === 0) {
      schoolClasses.value = []
      return
    }
    const { data: classRows, error } = await supabase
      .from('classes')
      .select('id, class_name, homeroom_teacher_id')
      .in('id', wantedIds)
    if (error) throw error
    // 本班排在最前，方便一眼选中
    schoolClasses.value = ((classRows ?? []) as typeof schoolClasses.value).sort(
      (classA, classB) =>
        Number(classB.id === userStore.boundClassId) - Number(classA.id === userStore.boundClassId),
    )
    // 教师下拉不提供"全部"选项，未选时默认落在自己的班
    if (!filterClassId.value) filterClassId.value = userStore.boundClassId || ''
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载班级列表失败')
  }
}

// ===== 成绩授权（班主任把本班成绩开放给本校其他老师）=====
const grantDialogVisible = ref(false)
const grantLoading = ref(false)
const grantSaving = ref(false)
/** 弹窗内列出的同校教师及其当前授权状态 */
const grantCandidates = ref<{ id: string; real_name: string; roleLabel: string; granted: boolean }[]>([])
/** 弹窗内被勾选（= 允许访问本班成绩）的教师 id */
const grantSelectedIds = ref<string[]>([])

/**
 * 打开成绩授权弹窗：列出本校教师（含学校管理员）并标出已授权的人。
 * 只列同校 —— 跨校账号既看不到、后端也不允许授权（fn_is_same_school_user）。
 * @returns 无返回值（副作用：写入 grantCandidates）
 */
async function openGrantDialog() {
  const targetClassId = effectiveClassId.value
  if (!targetClassId || !userStore.schoolId) return
  grantDialogVisible.value = true
  grantLoading.value = true
  try {
    const { data: teacherRows, error } = await supabase
      .from('profiles')
      .select('id, real_name, name, role')
      .eq('school_id', userStore.schoolId)
      .in('role', ['teacher', 'school_admin'])
      .order('real_name', { ascending: true })
    if (error) throw error
    const { data: grantRows, error: grantError } = await supabase
      .from('grade_access_grants')
      .select('teacher_id')
      .eq('class_id', targetClassId)
    if (grantError) throw grantError
    const grantedIds = new Set((grantRows ?? []).map((grant: any) => grant.teacher_id as string))
    grantCandidates.value = ((teacherRows ?? []) as any[])
      .filter((teacherRow) => teacherRow.id !== userStore.id)
      .map((teacherRow) => ({
        id: teacherRow.id,
        real_name: teacherRow.real_name || teacherRow.name || '未命名',
        roleLabel: teacherRow.role === 'school_admin' ? '学校管理员' : '教师',
        granted: grantedIds.has(teacherRow.id),
      }))
    grantSelectedIds.value = grantCandidates.value.filter((candidate) => candidate.granted).map((candidate) => candidate.id)
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载教师列表失败')
  } finally {
    grantLoading.value = false
  }
}

/**
 * 保存授权名单：按勾选差异做增删（插入容忍重复由唯一约束兜底，撤销按行 id 删除）。
 * @returns 无返回值
 */
async function saveGrants() {
  const targetClassId = effectiveClassId.value
  if (!targetClassId || !userStore.schoolId) return
  grantSaving.value = true
  try {
    const { data: existingRows, error: readError } = await supabase
      .from('grade_access_grants')
      .select('id, teacher_id')
      .eq('class_id', targetClassId)
    if (readError) throw readError
    const existingMap = new Map(((existingRows ?? []) as any[]).map((row) => [row.teacher_id as string, row.id as string]))
    const wantedIds = new Set(grantSelectedIds.value)

    const addedIds = Array.from(wantedIds).filter((teacherId) => !existingMap.has(teacherId))
    const removedRowIds = Array.from(existingMap.entries())
      .filter(([teacherId]) => !wantedIds.has(teacherId))
      .map(([, rowId]) => rowId)

    if (addedIds.length > 0) {
      const { error } = await supabase.from('grade_access_grants').insert(
        addedIds.map((teacherId) => ({
          school_id: userStore.schoolId,
          class_id: targetClassId,
          teacher_id: teacherId,
          granted_by: userStore.id,
        })),
      )
      if (error) throw error
    }
    if (removedRowIds.length > 0) {
      const { error } = await supabase.from('grade_access_grants').delete().in('id', removedRowIds)
      if (error) throw error
    }
    ElMessage.success(`授权已更新（新增 ${addedIds.length} 人，撤销 ${removedRowIds.length} 人）`)
    grantDialogVisible.value = false
    await loadSchoolClasses()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存授权失败')
  } finally {
    grantSaving.value = false
  }
}

const examOptions = ref<{ name: string; date: string }[]>([])
const currentExam = ref('')
const currentExamDate = ref('')

const subjectColumns = computed(() => {
  if (!currentExam.value) return []
  const subjectSet = new Set<string>()
  allScores.value
    .filter((score) => score.exam_name === currentExam.value)
    .forEach((score) => subjectSet.add(score.subject))
  return Array.from(subjectSet).sort()
})

const matrixRows = computed<MatrixRow[]>(() => {
  if (!currentExam.value) return []
  const examScores = allScores.value.filter((score) => score.exam_name === currentExam.value)
  const scoreMap = new Map<string, ScoreRow>()
  examScores.forEach((score) => scoreMap.set(`${score.student_id}|${score.subject}`, score))
  const subjectNames = subjectColumns.value
  return students.value.map((student) => {
    const cells: Record<string, MatrixCell> = {}
    let total = 0
    let scoreCount = 0
    subjectNames.forEach((subjectName) => {
      const score = scoreMap.get(`${student.id}|${subjectName}`)
      if (score) {
        cells[subjectName] = { id: score.id, score: score.score, full_score: score.full_score }
        total += score.score
        scoreCount++
      } else {
        cells[subjectName] = { score: null, full_score: 100 }
      }
    })
    return {
      student_id: student.id,
      student_name: student.student_name,
      cells,
      total,
      avg: scoreCount > 0 ? +(total / scoreCount).toFixed(1) : 0,
      scoreCount,
    }
  })
})

const totalScoreCells = computed(() =>
  matrixRows.value.reduce((sum, matrixRow) => sum + matrixRow.scoreCount, 0),
)

const classAvg = computed(() => {
  const scoredRows = matrixRows.value.filter((matrixRow) => matrixRow.scoreCount > 0)
  if (scoredRows.length === 0) return 0
  const total = scoredRows.reduce((sum, matrixRow) => sum + matrixRow.total, 0)
  const scoreCount = scoredRows.reduce((sum, matrixRow) => sum + matrixRow.scoreCount, 0)
  return scoreCount > 0 ? +(total / scoreCount).toFixed(1) : 0
})

const passRate = computed(() => {
  let totalCells = 0, passCells = 0
  matrixRows.value.forEach((matrixRow) => {
    Object.values(matrixRow.cells).forEach((cell) => {
      if (cell.score !== null) {
        totalCells++
        if (cell.score / cell.full_score >= 0.6) passCells++
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

/**
 * 打开单元格成绩编辑弹窗，并把该单元格已有成绩回填到弹窗表单
 * @param matrixRow 成绩矩阵中该学生所在行
 * @param subjectName 被点击的学科列名
 */
function openCellEditor(matrixRow: MatrixRow, subjectName: string) {
  const cell = matrixRow.cells[subjectName]
  cellDialogForm.value = {
    student_id: matrixRow.student_id,
    student_name: matrixRow.student_name,
    subject: subjectName,
    score: cell.score ?? 0,
    full_score: cell.full_score,
    score_id: cell.id,
  }
  cellDialogVisible.value = true
}

/**
 * 提交单元格成绩：已有成绩走更新、无成绩走新增，成功后刷新矩阵
 * @returns 无返回值（副作用：写库、关闭弹窗、重新加载数据）
 */
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
      const studentName = students.value.find((student) => student.id === cellDialogForm.value.student_id)?.student_name
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
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存失败')
  }
}

/**
 * 删除当前单元格对应的成绩记录（先二次确认，用户取消则直接返回）
 */
async function handleCellDelete() {
  if (!cellDialogForm.value.score_id) {
    ElMessage.warning('该单元格尚无成绩记录')
    return
  }
  try {
    await ElMessageBox.confirm('确定删除该条成绩吗？', '提示', { type: 'warning' })
  } catch {
    // 用户在确认框中点了「取消」，此处静默返回即可
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
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '删除失败')
  }
}

// ===== 新增考试 =====
const newExamVisible = ref(false)
const newExamForm = ref({ name: '', date: new Date().toISOString().slice(0, 10) })

/**
 * 打开「新增考试」弹窗，并重置考试名称与日期
 */
function openNewExam() {
  newExamForm.value = { name: '', date: new Date().toISOString().slice(0, 10) }
  newExamVisible.value = true
}

/**
 * 创建考试：校验名称非空且不重名后写入 localStorage，并自动切换为当前考试
 */
function handleNewExam() {
  if (!newExamForm.value.name.trim()) {
    ElMessage.warning('请输入考试名称')
    return
  }
  if (examOptions.value.find((examOption) => examOption.name === newExamForm.value.name.trim())) {
    ElMessage.warning('该考试名称已存在')
    return
  }
  const storageKey = 'MOCK_EXAMS'
  const storedExams = localStorage.getItem(storageKey)
  const examList: { name: string; date: string }[] = storedExams ? JSON.parse(storedExams) : []
  examList.push({ name: newExamForm.value.name.trim(), date: newExamForm.value.date })
  localStorage.setItem(storageKey, JSON.stringify(examList))
  examOptions.value = examList
  currentExam.value = newExamForm.value.name.trim()
  currentExamDate.value = newExamForm.value.date
  newExamVisible.value = false
  ElMessage.success(`已创建「${currentExam.value}」，可开始录入成绩`)
}

// ===== Excel 导入（宽表格式）=====
/**
 * 下载成绩导入模板：第一列为学生姓名，其余列按当前考试的学科生成示例分数
 */
function downloadTemplate() {
  const workbook = XLSX.utils.book_new()
  const subjectNames = subjectColumns.value.length > 0 ? subjectColumns.value : ['语文', '数学', '英语']
  const examName = currentExam.value || '本次考试'
  const headerRow = ['学生姓名', ...subjectNames]
  const sampleRow1 = ['张三', ...subjectNames.map(() => 85)]
  const sampleRow2 = ['李四', ...subjectNames.map(() => 90)]
  XLSX.utils.book_append_sheet(workbook, XLSX.utils.aoa_to_sheet([headerRow, sampleRow1, sampleRow2]), examName)
  XLSX.writeFile(workbook, `成绩导入_${examName}.xlsx`)
}

/**
 * 解析宽表 Excel 并批量覆盖式导入成绩
 * 第 1 行为表头（学生姓名 + 各学科列）；写入前先按当前考试名删除旧成绩再整批插入
 * @param file 用户在文件选择框选中的 xlsx/xls 文件
 * @returns 无返回值（副作用：删旧数据、写库、消息提示、刷新矩阵）
 */
async function handleImport(file: File) {
  if (!currentExam.value) {
    ElMessage.warning('请先选择或创建一个考试')
    return
  }
  const fileBuffer = await file.arrayBuffer()
  const workbook = XLSX.read(fileBuffer, { type: 'array' })
  const worksheet = workbook.Sheets[workbook.SheetNames[0]]
  const sheetRows = XLSX.utils.sheet_to_json(worksheet, { header: 1 }) as any[][]
  if (sheetRows.length < 2) {
    ElMessage.warning('模板内容为空')
    return
  }
  const headerCells = sheetRows[0].map((cellText) => String(cellText).trim())
  const importSubjects = headerCells.slice(1)

  const scoreRecords: ScoreRow[] = []
  const session = (await supabase.auth.getSession()).data.session
  const operatorId = session?.user.id

  for (let rowIndex = 1; rowIndex < sheetRows.length; rowIndex++) {
    const sheetRow = sheetRows[rowIndex]
    if (!sheetRow || sheetRow.length < 2) continue
    const name = String(sheetRow[0] ?? '').trim()
    if (!name) continue
    const student = students.value.find((candidate) => candidate.student_name === name)
    if (!student) {
      ElMessage.warning(`第 ${rowIndex + 1} 行：未找到学生「${name}」，已跳过`)
      continue
    }
    for (let subjectIdx = 0; subjectIdx < importSubjects.length; subjectIdx++) {
      const cellValue = sheetRow[subjectIdx + 1]
      if (cellValue === undefined || cellValue === null || cellValue === '') continue
      const score = Number(cellValue)
      if (isNaN(score)) continue
      scoreRecords.push({
        id: '',
        student_id: student.id,
        student_name: student.student_name,
        subject: importSubjects[subjectIdx],
        exam_name: currentExam.value,
        exam_date: currentExamDate.value,
        score,
        full_score: 100,
      })
    }
  }

  if (scoreRecords.length === 0) {
    ElMessage.warning('没有可导入的有效记录')
    return
  }

  try {
    const { data: existingRows } = await supabase
      .from('student_scores')
      .select('id')
      .eq('exam_name', currentExam.value)
    const existingScoreIds = (existingRows ?? []).map((scoreRow: any) => scoreRow.id)
    if (existingScoreIds.length > 0) {
      await supabase.from('student_scores').delete().in('id', existingScoreIds)
    }
    const { error } = await supabase.from('student_scores').insert(
      scoreRecords.map((record) => ({
        student_id: record.student_id,
        student_name: record.student_name,
        subject: record.subject,
        exam_name: record.exam_name,
        exam_date: record.exam_date,
        score: record.score,
        full_score: record.full_score,
        school_id: userStore.schoolId,
        class_id: effectiveClassId.value,
        operator_user_id: operatorId,
      })),
    )
    if (error) throw error
    ElMessage.success(`成功导入 ${scoreRecords.length} 条成绩（已覆盖 ${existingScoreIds.length} 条旧数据）`)
    await loadAll()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '导入失败')
  }
}

/**
 * 文件选择框的 change 事件处理：取到文件后交给批量导入，并在完成后清空 input
 * @param changeEvent input 元素的 change 事件
 */
function onFileChange(changeEvent: Event) {
  const fileInput = changeEvent.target as HTMLInputElement
  const file = fileInput.files?.[0]
  if (file) handleImport(file).finally(() => { fileInput.value = '' })
}

/**
 * 导出当前考试的宽表成绩（姓名 + 各学科 + 总分 + 平均分）
 */
function handleExport() {
  if (!currentExam.value || matrixRows.value.length === 0) {
    ElMessage.warning('请先选择有成绩的考试')
    return
  }
  const headerRow = ['学生姓名', ...subjectColumns.value, '总分', '平均分']
  const exportRows = matrixRows.value.map((matrixRow) => {
    const scoreValues = subjectColumns.value.map((subjectName) => {
      const cell = matrixRow.cells[subjectName]
      return cell.score !== null ? cell.score : ''
    })
    return [matrixRow.student_name, ...scoreValues, matrixRow.total, matrixRow.avg]
  })
  exportToExcel([headerRow, ...exportRows], `成绩_${currentExam.value}_${Date.now()}.xlsx`)
}

// ===== 数据加载 =====
/**
 * 加载学生列表：教师按 class_id 过滤，学校管理员按班级（未选班级时按 school_id）过滤
 * @returns 无返回值，成功后写入 students 列表
 */
async function loadStudents() {
  if (!userStore.schoolId) return
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
      // 教师：按当前操作班级取学生（本班 或 已被授权的班）
      if (!effectiveClassId.value) return
      query = query.eq('class_id', effectiveClassId.value)
    }
    const { data: studentRows, error } = await query
    if (error) throw error
    students.value = (studentRows ?? []) as StudentOpt[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载学生列表失败')
  }
}

/**
 * 加载全部成绩记录（按考试日期、学科排序），并用学生列表补齐 student_name
 * @returns 无返回值，成功后写入 allScores，并在 finally 中复位 loading
 */
async function loadAllScores() {
  if (!userStore.schoolId) return
  loading.value = true
  try {
    const { data: scoreRows, error } = await supabase
      .from('student_scores')
      .select('*')
      .order('exam_date', { ascending: true })
      .order('subject', { ascending: true })
    if (error) throw error
    let scoreList = (scoreRows ?? []) as ScoreRow[]
    const stuMap: Record<string, string> = {}
    students.value.forEach((student) => { stuMap[student.id] = student.student_name })
    scoreList.forEach((score) => { if (!score.student_name) score.student_name = stuMap[score.student_id] })
    allScores.value = scoreList
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载成绩失败')
  } finally {
    loading.value = false
  }
}

/**
 * 组装考试下拉：合并 localStorage 中自建的考试与成绩里出现过的考试，按日期倒序
 */
function loadExamOptions() {
  const storedExams = localStorage.getItem('MOCK_EXAMS')
  let examList: { name: string; date: string }[] = storedExams ? JSON.parse(storedExams) : []
  const existingNames = new Set(examList.map((examOption) => examOption.name))
  allScores.value.forEach((score) => {
    if (!existingNames.has(score.exam_name)) {
      examList.push({ name: score.exam_name, date: score.exam_date })
      existingNames.add(score.exam_name)
    }
  })
  examList.sort((examA, examB) => examB.date.localeCompare(examA.date))
  examOptions.value = examList
  if (!currentExam.value && examList.length > 0) {
    currentExam.value = examList[0].name
    currentExamDate.value = examList[0].date
  }
}

/**
 * 页面数据总入口：先加载成绩，再据此刷新考试下拉
 */
async function loadAll() {
  await loadAllScores()
  loadExamOptions()
}

/**
 * 切换考试时同步该考试对应的日期（用于新增成绩时的 exam_date）
 */
function onExamChange() {
  const examOption = examOptions.value.find((exam) => exam.name === currentExam.value)
  currentExamDate.value = examOption?.date || ''
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
            v-for="examOption in examOptions"
            :key="examOption.name"
            :label="examOption.name + '（' + (examOption.date || '无日期') + '）'"
            :value="examOption.name"
          />
        </el-select>
        <el-button type="primary" :icon="Plus" @click="openNewExam">新增考试</el-button>
        <el-tag v-if="currentExamDate" type="info" effect="plain">
          {{ new Date(currentExamDate).toLocaleDateString('zh-CN') }}
        </el-tag>
        <el-select
          v-if="userStore.role === 'school_admin' || schoolClasses.length > 1"
          v-model="filterClassId"
          :clearable="userStore.role === 'school_admin'"
          :placeholder="userStore.role === 'school_admin' ? '按班级筛选' : '切换班级'"
          style="width: 200px"
          size="small"
        >
          <el-option v-if="userStore.role === 'school_admin'" label="全部班级" value="" />
          <el-option
            v-for="classItem in schoolClasses"
            :key="classItem.id"
            :label="classItem.class_name"
            :value="classItem.id"
          />
        </el-select>
        <el-button
          v-if="canGrantForCurrentClass"
          :icon="Key"
          size="small"
          @click="openGrantDialog"
        >
          成绩授权
        </el-button>
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
          <template #default="{ row: matrixRow }">
            <div class="student-cell">
              <div class="student-avatar">{{ (matrixRow as MatrixRow).student_name.charAt(0) }}</div>
              <div class="student-name">{{ (matrixRow as MatrixRow).student_name }}</div>
            </div>
          </template>
        </el-table-column>

        <el-table-column
          v-for="subjectName in subjectColumns"
          :key="subjectName"
          :label="subjectName"
          :width="110"
          align="center"
        >
          <template #default="{ row: matrixRow }">
            <div class="score-cell" :class="getScoreClass((matrixRow as MatrixRow).cells[subjectName])" @click="openCellEditor(matrixRow as MatrixRow, subjectName)">
              <template v-if="(matrixRow as MatrixRow).cells[subjectName].score !== null">
                <span class="score-num">{{ (matrixRow as MatrixRow).cells[subjectName].score }}</span>
                <span class="score-full">/ {{ (matrixRow as MatrixRow).cells[subjectName].full_score }}</span>
              </template>
              <template v-else>
                <span class="score-empty">+ 录入</span>
              </template>
            </div>
          </template>
        </el-table-column>

        <el-table-column label="总分" width="100" align="center" fixed="right">
          <template #default="{ row: matrixRow }"><span class="score-num total">{{ (matrixRow as MatrixRow).total }}</span></template>
        </el-table-column>
        <el-table-column label="平均分" width="100" align="center" fixed="right">
          <template #default="{ row: matrixRow }"><span class="score-num avg">{{ (matrixRow as MatrixRow).avg }}</span></template>
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

    <!-- 成绩授权弹窗（仅本班班主任可见）-->
    <el-dialog v-model="grantDialogVisible" title="成绩授权" width="520px" destroy-on-close>
      <el-alert
        type="info"
        :closable="false"
        show-icon
        style="margin-bottom: 12px"
      >
        <template #title>
          被勾选的老师可以查看并录入「{{ schoolClasses.find((c) => c.id === effectiveClassId)?.class_name || '本班' }}」的成绩。
          只能授权本校老师。
        </template>
      </el-alert>
      <div v-loading="grantLoading" style="min-height: 120px">
        <el-empty v-if="!grantLoading && grantCandidates.length === 0" description="本校暂无可授权的老师" />
        <el-checkbox-group v-model="grantSelectedIds" v-else>
          <div
            v-for="candidate in grantCandidates"
            :key="candidate.id"
            class="grant-row"
          >
            <el-checkbox :value="candidate.id">
              <span class="grant-name">{{ candidate.real_name }}</span>
              <el-tag size="small" type="info" effect="plain" style="margin-left: 8px">
                {{ candidate.roleLabel }}
              </el-tag>
            </el-checkbox>
          </div>
        </el-checkbox-group>
      </div>
      <template #footer>
        <el-button @click="grantDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="grantSaving" @click="saveGrants">保存授权</el-button>
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
/* 成绩授权弹窗 */
.grant-row { padding: 6px 4px; border-bottom: 1px solid var(--el-border-color-lighter); }
.grant-row:last-child { border-bottom: none; }
.grant-name { font-weight: 500; }
</style>
