<script setup lang="ts">
import { ref, computed, onMounted, watch, nextTick } from 'vue'
import { ElMessage } from 'element-plus'
import {
  Search,
  Download,
  ArrowLeft,
  ArrowRight,
  ArrowUp,
  ArrowDown,
  DocumentChecked,
  Plus,
  Delete,
  Setting,
} from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'
import * as XLSX from 'xlsx'

const userStore = useUserStore()

interface ClassRow {
  id: string
  name: string
  class_name?: string
  grade?: string
  gradeNum: number | null
  gradeLabel: string
}

interface InspectionRecord {
  id: string
  class_id: string
  inspect_date: string
  category: string
  score: number
  remark?: string | null
}

interface CategoryRow {
  id: string
  school_id: string
  name: string
  base_score: number
  sort_order: number
  is_active: boolean
}

interface DayInputRow {
  classId: string
  className: string
  gradeLabel: string
  scores: Record<string, number | null>
  remark: string
}

interface WeekDayInfo {
  label: string
  date: string
  short: string
}

interface WeekMatrixRow {
  class: ClassRow
  days: Record<string, Record<string, number | undefined>>
  total: number
  rank: number
  remark: string
}

interface RangeRow {
  class: ClassRow
  total: number
  rank: number
  remark: string
}

const DEFAULT_CATEGORY_NAMES = [
  '教室卫生',
  '包干区',
  '课间操',
  '眼保健操',
  '仪容仪表',
  '安全',
  '出勤',
  '其他',
]

// 8 项默认基础分（截图：教室卫生 2 分，其他 1 分，合计 10 分）
const DEFAULT_BASE_SCORES: Record<string, number> = {
  教室卫生: 2,
  包干区: 1,
  课间操: 1,
  眼保健操: 1,
  仪容仪表: 1,
  安全: 1,
  出勤: 1,
  其他: 1,
}

const WEEKDAY_LABELS = ['周一', '周二', '周三', '周四', '周五']

const activeTab = ref<'daily' | 'weekly' | 'range'>('daily')
const loading = ref(false)
const saving = ref(false)
const classes = ref<ClassRow[]>([])
const categories = ref<CategoryRow[]>([])

// 管理检查项目对话框
const catDialogVisible = ref(false)
const catSaving = ref(false)
const editingCats = ref<CategoryRow[]>([])
const newCatName = ref('')
const newCatBaseScore = ref(1)

// 按天
const selectedDate = ref<string>(formatDate(new Date()))
const dayRecordsMap = ref<Map<string, InspectionRecord>>(new Map())

// 按周
const weekAnchorDate = ref<string>(formatDate(new Date()))
const weekRecords = ref<InspectionRecord[]>([])

// 自定义范围
const rangeDates = ref<[string, string] | null>(null)
const rangeRecords = ref<InspectionRecord[]>([])
const rangeQueried = ref(false)

/**
 * 把日期对象格式化为 YYYY-MM-DD 字符串（本地时区，不做 UTC 转换）。
 * @param date 日期对象
 * @returns YYYY-MM-DD 格式字符串，用于 inspect_date 查询与展示
 */
function formatDate(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

/**
 * 把 YYYY-MM-DD 字符串解析为本地日期对象。
 * @param dateText YYYY-MM-DD 格式字符串
 * @returns 对应的 Date 对象（月份已做 0 基修正）
 */
function parseDate(dateText: string): Date {
  const [year, month, day] = dateText.split('-').map(Number)
  return new Date(year, month - 1, day)
}

/**
 * 取某一天所在周的周一（0 点整），作为「按周统计」的起点。
 * @param date 周内任意一天
 * @returns 该周周一的 Date 对象
 */
function getMondayOfWeek(date: Date): Date {
  const weekDay = date.getDay()
  const dayOffset = (weekDay + 6) % 7
  const monday = new Date(date)
  monday.setDate(date.getDate() - dayOffset)
  monday.setHours(0, 0, 0, 0)
  return monday
}

/**
 * 在给定日期上偏移若干天。
 * @param baseDate 基准日期
 * @param offsetDays 偏移天数（可为负）
 * @returns 偏移后的新 Date 对象
 */
function addDays(baseDate: Date, offsetDays: number): Date {
  const resultDate = new Date(baseDate)
  resultDate.setDate(baseDate.getDate() + offsetDays)
  return resultDate
}

/**
 * 计算某一天所属的 ISO 周序号（周一为一周开始）。
 * @param date 目标日期
 * @returns ISO 周序号（如第 12 周返回 12）
 */
function getISOWeek(date: Date): number {
  const normalizedDate = new Date(date.valueOf())
  normalizedDate.setHours(0, 0, 0, 0)
  normalizedDate.setDate(normalizedDate.getDate() + 4 - ((normalizedDate.getDay() + 6) % 7))
  const yearStart = new Date(normalizedDate.getFullYear(), 0, 1)
  const weekNo = Math.ceil((((normalizedDate.valueOf() - yearStart.valueOf()) / 86400000) + 1) / 7)
  return weekNo
}

/**
 * 从班级名称中解析年级数字（取开头的阿拉伯数字，如「3班」得到 3）。
 * @param className 班级名称或年级文本
 * @returns 年级数字；无法解析时返回 null
 */
function gradeNumberFromName(className: string): number | null {
  const matched = className.match(/^(\d)/)
  if (matched) return Number(matched[1])
  return null
}

/**
 * 由年级数字得到年级显示名；若班级已带 grade 字段则优先使用。
 * @param gradeNum 年级数字，null 表示无法识别
 * @param grade 班级表里的年级文本（可选）
 * @returns 年级显示名，如「三年级」；无法识别时返回「其它」
 */
function gradeLabelFromNum(gradeNum: number | null, grade?: string): string {
  if (grade) return grade
  if (gradeNum === null) return '其它'
  const gradeNameMap: Record<number, string> = {
    1: '一年级', 2: '二年级', 3: '三年级', 4: '四年级', 5: '五年级',
    6: '六年级', 7: '七年级', 8: '八年级', 9: '九年级',
  }
  return gradeNameMap[gradeNum] || `第${gradeNum}年级`
}

/**
 * 取单元格分数的样式类名：扣分红色、加分绿色、0 与空值中性。
 * @param scoreDelta 加减分值，可为空
 * @returns CSS 类名（score-neg / score-pos / 空字符串）
 */
function dayScoreClass(scoreDelta: number | undefined | null): string {
  if (scoreDelta === undefined || scoreDelta === null) return ''
  if (scoreDelta < 0) return 'score-neg'
  if (scoreDelta > 0) return 'score-pos'
  return ''
}

/** 全部项目每天的基础分总和（即当天「满分」），用于按天登分的满分对比 */
const totalBaseScore = computed(() => {
  return Math.round(
    categories.value.reduce((sum, category) => sum + (Number(category.base_score) || 0), 0) * 100
  ) / 100
})

/**
 * 计算某班某项目的「实际得分」：项目基础分 + 加减分；未填写的项目按基础分计。
 * @param row 按天登分的一行数据（含各项目的加减分）
 * @param catName 检查项目名称
 * @returns 实际得分；项目已不存在时返回 null
 */
function effectiveDayScore(
  row: DayInputRow,
  catName: string
): number | null {
  const cat = categories.value.find((item) => item.name === catName)
  if (!cat) return null
  const adj = row.scores[catName]
  const base = Number(cat.base_score) || 0
  if (adj === null || adj === undefined) return base
  return Math.round((base + Number(adj)) * 100) / 100
}

/**
 * 计算按周统计表格中某班某项目某天的「实际得分」。
 * 与按天口径一致：单元格未填写时按项目基础分计。
 * @param cellValue 周表格中该单元格的加减分，undefined 表示无记录
 * @param catName 检查项目名称
 * @returns 实际得分；项目已不存在时返回 null
 */
function effectiveWeekDayScore(
  cellValue: number | undefined,
  catName: string
): number | null {
  const cat = categories.value.find((item) => item.name === catName)
  if (!cat) return null
  const base = Number(cat.base_score) || 0
  if (cellValue === undefined) return base
  return Math.round((base + Number(cellValue)) * 100) / 100
}

/**
 * 加载本校班级列表，并解析出年级数字与年级显示名（用于按年级排名）。
 * @returns 无返回值，结果写入响应式变量 classes
 */
async function loadClasses() {
  if (!userStore.schoolId) return
  loading.value = true
  try {
    const { data: classData, error } = await supabase
      .from('classes')
      .select('id, name, class_name, grade')
      .eq('school_id', userStore.schoolId)
      .order('name', { ascending: true })
    if (error) throw error
    classes.value = ((classData ?? []) as any[]).map((cls) => {
      const resolvedClassName = cls.name || cls.class_name || ''
      const parsedGradeNum = gradeNumberFromName(resolvedClassName) ?? (cls.grade ? gradeNumberFromName(cls.grade) : null)
      return {
        id: cls.id,
        name: resolvedClassName,
        class_name: cls.class_name,
        grade: cls.grade,
        gradeNum: parsedGradeNum,
        gradeLabel: gradeLabelFromNum(parsedGradeNum, cls.grade),
      }
    })
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载班级列表失败')
  } finally {
    loading.value = false
  }
}

/**
 * 加载本校检查项目；若该校还没有任何项目，则自动预填 8 项默认项目后重新加载。
 * @returns 当前生效的检查项目数组（同时写入响应式变量 categories）
 */
async function loadCategories(): Promise<CategoryRow[]> {
  if (!userStore.schoolId) return []
  const { data: categoryData, error } = await supabase
    .from('inspection_categories')
    .select('id, school_id, name, base_score, sort_order, is_active')
    .eq('school_id', userStore.schoolId)
    .order('sort_order', { ascending: true })
    .order('name', { ascending: true })
  if (error) {
    ElMessage.error(error.message || '加载检查项目失败')
    return []
  }
  const categoryList = (categoryData ?? []) as CategoryRow[]
  categories.value = categoryList
  // 首次进入：学校还没有任何项目，自动预填 8 项
  if (categoryList.length === 0) {
    await seedDefaultCategories()
    const reloaded = await loadCategories()
    return reloaded
  }
  return categoryList
}

/**
 * 预填 8 项默认检查项目及基础分（仅在全校无项目时调用）。
 * @returns 无返回值，直接写入 inspection_categories 表
 */
async function seedDefaultCategories() {
  if (!userStore.schoolId) return
  const defaultCategoryRows = DEFAULT_CATEGORY_NAMES.map((categoryName, orderIndex) => ({
    school_id: userStore.schoolId,
    name: categoryName,
    base_score: DEFAULT_BASE_SCORES[categoryName] ?? 1,
    sort_order: orderIndex,
    is_active: true,
  }))
  const { error } = await supabase
    .from('inspection_categories')
    .upsert(defaultCategoryRows, { onConflict: 'school_id,name', ignoreDuplicates: true })
  if (error) {
    ElMessage.error(error.message || '初始化检查项目失败')
  }
}

/**
 * 生成「班级 + 检查项目」的组合键，用于按天记录的快速定位。
 * @param classId 班级 id
 * @param category 检查项目名称
 * @returns 形如 `班级id|项目名` 的字符串键
 */
function makeRecordKey(classId: string, category: string) {
  return `${classId}|${category}`
}

/**
 * 加载所选日期当天的检查记录，并按「班级|项目」组合键缓存到 Map 中。
 * @returns 无返回值，结果写入响应式变量 dayRecordsMap
 */
async function loadDayRecords() {
  if (!userStore.schoolId) return
  loading.value = true
  try {
    const { data: recordData, error } = await supabase
      .from('class_inspection_records')
      .select('id, class_id, inspect_date, category, score, remark')
      .eq('school_id', userStore.schoolId)
      .eq('inspect_date', selectedDate.value)
    if (error) throw error
    const recordMap = new Map<string, InspectionRecord>()
    ;((recordData ?? []) as any[]).forEach((record) => {
      recordMap.set(makeRecordKey(record.class_id, record.category), record)
    })
    dayRecordsMap.value = recordMap
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载当天扣分记录失败')
  } finally {
    loading.value = false
  }
}

/** 按天登分表格的行数据：每个班级一行，按项目列出加减分与备注 */
const dayInputRows = computed<DayInputRow[]>(() => {
  const catList = categories.value
  return classes.value.map((cls) => {
    const scores: Record<string, number | null> = {}
    let remark = ''
    for (const cat of catList) {
      const record = dayRecordsMap.value.get(makeRecordKey(cls.id, cat.name))
      if (record) {
        scores[cat.name] = Number(record.score)
        if (record.remark && !remark) remark = record.remark
      } else {
        scores[cat.name] = null
      }
    }
    return {
      classId: cls.id,
      className: cls.name,
      gradeLabel: cls.gradeLabel,
      scores,
      remark,
    }
  })
})

/**
 * 取某班某项目在输入框中的值（null 转为 undefined，供 el-input-number 显示为空占位）。
 * @param row 按天登分的一行数据
 * @param key 检查项目名称
 * @returns 加减分值；无填写时返回 undefined
 */
function scoreInputValue(row: DayInputRow, key: string): number | undefined {
  const rawDelta = row.scores[key]
  return rawDelta === null || rawDelta === undefined ? undefined : rawDelta
}

/**
 * 计算班级某行的当日得分：各项基础分之和 + 各项加减分。
 * @param row 按天登分的一行数据
 * @returns 保留两位小数的当日得分
 */
function dayRowTotal(row: DayInputRow): number {
  const catList = categories.value
  let total = 0
  for (const cat of catList) {
    const base = Number(cat.base_score) || 0
    const adj = row.scores[cat.name]
    total += base + (adj === null || adj === undefined ? 0 : Number(adj))
  }
  return Math.round(total * 100) / 100
}

/**
 * 接收输入框的加减分变更，写回该行对应项目（空值统一记为 null）。
 * @param row 按天登分的一行数据
 * @param key 检查项目名称
 * @param inputValue 输入框的原始值（数字或空字符串）
 * @returns 无返回值，直接修改 row.scores
 */
function onScoreInput(row: DayInputRow, key: string, inputValue: number | undefined | string) {
  if (inputValue === '' || inputValue === undefined || inputValue === null) {
    row.scores[key] = null
  } else {
    const parsedScore = Number(inputValue)
    row.scores[key] = isNaN(parsedScore) ? null : parsedScore
  }
}

/**
 * 保存所选日期的按天登分结果。
 * 已填写加减分的项目走 upsert（冲突键 class_id + inspect_date + category）；
 * 被清空的项目若库中已存在记录则删除，保证「清空即删除」的语义。
 * @returns 无返回值，成功后重新加载当天记录
 */
async function saveDayScores() {
  if (!userStore.schoolId) return
  const session = (await supabase.auth.getSession()).data.session
  if (!session) {
    ElMessage.error('未登录')
    return
  }
  saving.value = true
  try {
    const upserts: any[] = []
    const deletes: string[] = []
    const base = {
      school_id: userStore.schoolId,
      inspect_date: selectedDate.value,
      operator_user_id: session.user.id,
    }
    const catList = categories.value
    for (const row of dayInputRows.value) {
      const remark = row.remark?.trim() || null
      for (const cat of catList) {
        const scoreDelta = row.scores[cat.name]
        const existingRecord = dayRecordsMap.value.get(makeRecordKey(row.classId, cat.name))
        if (scoreDelta === null || scoreDelta === undefined) {
          if (existingRecord) deletes.push(existingRecord.id)
        } else {
          upserts.push({
            ...base,
            class_id: row.classId,
            category: cat.name,
            score: Number(scoreDelta),
            remark,
          })
        }
      }
    }
    if (upserts.length > 0) {
      const { error } = await supabase
        .from('class_inspection_records')
        .upsert(upserts, { onConflict: 'class_id,inspect_date,category' })
      if (error) throw error
    }
    if (deletes.length > 0) {
      const { error } = await supabase
        .from('class_inspection_records')
        .delete()
        .in('id', deletes)
      if (error) throw error
    }
    ElMessage.success('保存成功')
    await loadDayRecords()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存失败')
  } finally {
    saving.value = false
  }
}

/**
 * 按天数前后切换「按天登分」的当前日期。
 * @param offsetDays 偏移天数（-1 前一天、1 后一天）
 * @returns 无返回值，直接更新响应式变量 selectedDate
 */
function shiftDate(offsetDays: number) {
  const currentDate = parseDate(selectedDate.value)
  selectedDate.value = formatDate(addDays(currentDate, offsetDays))
}

const weekDays = computed<WeekDayInfo[]>(() => {
  const mon = getMondayOfWeek(parseDate(weekAnchorDate.value))
  return WEEKDAY_LABELS.map((label, dayIndex) => {
    const dayDate = addDays(mon, dayIndex)
    return { label, date: formatDate(dayDate), short: `${dayDate.getMonth() + 1}/${dayDate.getDate()}` }
  })
})

const weekTitle = computed(() => {
  const days = weekDays.value
  if (!days.length) return ''
  const start = days[0].date
  const end = days[days.length - 1].date
  const weekNo = getISOWeek(parseDate(start))
  return `班级检查扣分表（第${weekNo}周）${start} 至 ${end}`
})

// 一周（5 天）每天基础分总和 = 5 × sum(base_score)
const weekFullBaseScore = computed(() => Math.round(totalBaseScore.value * weekDays.value.length * 100) / 100)

/**
 * 加载当前周（周一至周五）内的检查记录，供按周统计表格使用。
 * @returns 无返回值，结果写入响应式变量 weekRecords
 */
async function loadWeekRecords() {
  if (!userStore.schoolId) return
  loading.value = true
  try {
    const days = weekDays.value
    const start = days[0]?.date
    const end = days[days.length - 1]?.date
    if (!start || !end) return
    const { data: recordData, error } = await supabase
      .from('class_inspection_records')
      .select('id, class_id, inspect_date, category, score, remark')
      .eq('school_id', userStore.schoolId)
      .gte('inspect_date', start)
      .lte('inspect_date', end)
    if (error) throw error
    weekRecords.value = (recordData ?? []) as InspectionRecord[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载本周扣分记录失败')
  } finally {
    loading.value = false
  }
}

/**
 * 构造按周统计表格的行数据：每个班级一行，按「日期 + 项目」铺开加减分，并算出周总分与名次。
 * 周总分以一周基础分总和为起点，逐条累加记录里的加减分；名次按总分降序、同分并列。
 * @param records 当前周范围内的检查记录
 * @returns 已按总分降序排列、并写好 rank 的班级行数组
 */
function buildMatrixRows(records: InspectionRecord[]): WeekMatrixRow[] {
  const catList = categories.value
  const fullBase = weekFullBaseScore.value // 一周基础分总和（5 × 各项基础分之和）
  const matrixRows = classes.value.map((cls) => {
    const days: Record<string, Record<string, number | undefined>> = {}
    let total = fullBase
    let remark = ''
    for (const weekDay of weekDays.value) {
      days[weekDay.date] = {}
      for (const cat of catList) days[weekDay.date][cat.name] = undefined
    }
    records
      .filter((record) => record.class_id === cls.id)
      .forEach((record) => {
        total += Number(record.score) || 0
        if (record.remark && !remark) remark = record.remark
        const dayCells = days[record.inspect_date]
        if (!dayCells) return
        // 仅纳入学校当前已配置的项目；旧分类数据自然汇总到 total
        if (catList.some((category) => category.name === record.category)) {
          dayCells[record.category] = Number(record.score)
        }
      })
    // 消除浮点累加误差
    total = Math.round(total * 100) / 100
    return { class: cls, days, total, rank: 0, remark }
  })
  matrixRows.sort((a, b) => b.total - a.total)
  let rank = 0
  let prevScore: number | null = null
  matrixRows.forEach((row, rowIndex) => {
    if (prevScore === null || row.total !== prevScore) {
      rank = rowIndex + 1
      prevScore = row.total
    }
    row.rank = rank
  })
  return matrixRows
}

const weekMatrixRows = computed(() => buildMatrixRows(weekRecords.value))

const gradeRankRows = computed(() => {
  const grouped = new Map<string, WeekMatrixRow[]>()
  for (const matrixRow of weekMatrixRows.value) {
    const key = matrixRow.class.gradeLabel
    if (!grouped.has(key)) grouped.set(key, [])
    grouped.get(key)!.push(matrixRow)
  }
  const gradeRankList: { grade: string; rank: number; className: string; total: number }[] = []
  const sortedGrades = Array.from(grouped.entries()).sort((entryA, entryB) => {
    const gradeNumA = entryA[1][0]?.class.gradeNum ?? 99
    const gradeNumB = entryB[1][0]?.class.gradeNum ?? 99
    return gradeNumA - gradeNumB
  })
  for (const [grade, gradeClassRows] of sortedGrades) {
    gradeClassRows.sort((a, b) => b.total - a.total)
    let rank = 0
    let previousTotal: number | null = null
    gradeClassRows.forEach((rankRow, rowIndex) => {
      if (previousTotal === null || rankRow.total !== previousTotal) {
        rank = rowIndex + 1
        previousTotal = rankRow.total
      }
      gradeRankList.push({ grade, rank, className: rankRow.class.name, total: rankRow.total })
    })
  }
  return gradeRankList
})

/**
 * 按周前后切换「按周统计」的锚点日期（仍取该日所在周的周一）。
 * @param offsetDays 偏移天数（-7 上一周、7 下一周）
 * @returns 无返回值，直接更新响应式变量 weekAnchorDate
 */
function shiftWeek(offsetDays: number) {
  const currentDate = parseDate(weekAnchorDate.value)
  weekAnchorDate.value = formatDate(addDays(currentDate, offsetDays))
}

/**
 * 加载自定义日期范围内的检查记录（自定义范围页点击「查询」时调用）。
 * @returns 无返回值，结果写入响应式变量 rangeRecords，并置 rangeQueried 为 true
 */
async function loadRangeRecords() {
  if (!userStore.schoolId || !rangeDates.value || rangeDates.value.length !== 2) return
  loading.value = true
  rangeQueried.value = true
  try {
    const [start, end] = rangeDates.value
    const { data: recordData, error } = await supabase
      .from('class_inspection_records')
      .select('id, class_id, inspect_date, category, score, remark')
      .eq('school_id', userStore.schoolId)
      .gte('inspect_date', start)
      .lte('inspect_date', end)
    if (error) throw error
    rangeRecords.value = (recordData ?? []) as InspectionRecord[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载区间扣分记录失败')
  } finally {
    loading.value = false
  }
}

const rangeDays = computed(() => {
  if (!rangeDates.value || rangeDates.value.length !== 2) return 0
  const [startDate, endDate] = rangeDates.value
  const startTime = parseDate(startDate).getTime()
  const endTime = parseDate(endDate).getTime()
  return Math.max(0, Math.round((endTime - startTime) / 86400000) + 1)
})

const rangeFullBaseScore = computed(() => Math.round(totalBaseScore.value * rangeDays.value * 100) / 100)

const rangeRows = computed<RangeRow[]>(() => {
  const fullBase = rangeFullBaseScore.value
  const rangeTableRows = classes.value.map((cls) => {
    const classRecords = rangeRecords.value.filter((record) => record.class_id === cls.id)
    const total =
      Math.round((fullBase + classRecords.reduce((sum, record) => sum + (Number(record.score) || 0), 0)) * 100) / 100
    const remark = classRecords.find((record) => record.remark)?.remark || ''
    return { class: cls, total, rank: 0, remark }
  })
  rangeTableRows.sort((a, b) => b.total - a.total)
  let rank = 0
  let previousTotal: number | null = null
  rangeTableRows.forEach((row, rowIndex) => {
    if (previousTotal === null || row.total !== previousTotal) {
      rank = rowIndex + 1
      previousTotal = row.total
    }
    row.rank = rank
  })
  return rangeTableRows
})

const rangeGradeRankRows = computed(() => {
  const grouped = new Map<string, RangeRow[]>()
  for (const rangeRow of rangeRows.value) {
    const key = rangeRow.class.gradeLabel
    if (!grouped.has(key)) grouped.set(key, [])
    grouped.get(key)!.push(rangeRow)
  }
  const gradeRankList: { grade: string; rank: number; className: string; total: number }[] = []
  const sortedGrades = Array.from(grouped.entries()).sort((entryA, entryB) => {
    const gradeNumA = entryA[1][0]?.class.gradeNum ?? 99
    const gradeNumB = entryB[1][0]?.class.gradeNum ?? 99
    return gradeNumA - gradeNumB
  })
  for (const [grade, gradeClassRows] of sortedGrades) {
    gradeClassRows.sort((a, b) => b.total - a.total)
    let rank = 0
    let previousTotal: number | null = null
    gradeClassRows.forEach((rankRow, rowIndex) => {
      if (previousTotal === null || rankRow.total !== previousTotal) {
        rank = rowIndex + 1
        previousTotal = rankRow.total
      }
      gradeRankList.push({ grade, rank, className: rankRow.class.name, total: rankRow.total })
    })
  }
  return gradeRankList
})

/**
 * 导出「按周统计」Excel：两行表头（首行为标题并跨列合并，次行为各项目分组空行）+ 班级数据行。
 * @returns 无返回值，直接触发浏览器下载
 */
function exportWeeklyExcel() {
  const days = weekDays.value
  const catList = categories.value
  const totalCols = 2 + days.length * catList.length + 3
  const header1: string[] = ['序号', '班级']
  days.forEach(() => catList.forEach((category) => header1.push(category.name)))
  header1.push('总分', '名次', '备注')
  const titleRow = [weekTitle.value]
  const header2: string[] = ['', '']
  days.forEach(() => catList.forEach(() => header2.push('')))
  header2.push('', '', '')
  const body = weekMatrixRows.value.map((matrixRow, rowIndex) => {
    const excelRow: (string | number)[] = [rowIndex + 1, matrixRow.class.name]
    days.forEach((weekDay) => {
      const cell = matrixRow.days[weekDay.date] || {}
      catList.forEach((category) => excelRow.push(cell[category.name] ?? ''))
    })
    excelRow.push(matrixRow.total, matrixRow.rank, matrixRow.remark || '')
    return excelRow
  })
  const wb = XLSX.utils.book_new()
  const ws = XLSX.utils.aoa_to_sheet([titleRow, header2, header1, ...body])
  const merges: any[] = [{ s: { r: 0, c: 0 }, e: { r: 0, c: totalCols - 1 } }]
  let mergeColIndex = 2
  days.forEach(() => {
    merges.push({ s: { r: 1, c: mergeColIndex }, e: { r: 1, c: mergeColIndex + catList.length - 1 } })
    mergeColIndex += catList.length
  })
  ws['!merges'] = merges
  const colWidths: any[] = [{ wch: 6 }, { wch: 10 }]
  days.forEach(() => catList.forEach(() => colWidths.push({ wch: 9 })))
  colWidths.push({ wch: 8 }, { wch: 6 }, { wch: 16 })
  ws['!cols'] = colWidths
  XLSX.utils.book_append_sheet(wb, ws, '班级检查扣分')
  XLSX.writeFile(wb, `班级检查扣分_第${getISOWeek(parseDate(days[0].date))}周_${Date.now()}.xlsx`)
  ElMessage.success('导出成功')
}

/**
 * 导出「自定义范围」Excel：名次/班级/年级 + 各项目加减分合计 + 区间总分与备注。
 * @returns 无返回值，直接触发浏览器下载
 */
function exportRangeExcel() {
  if (!rangeDates.value) return
  const [rangeStart, rangeEnd] = rangeDates.value
  const catList = categories.value
  const header: string[] = ['名次', '班级', '年级']
  catList.forEach((category) => header.push(category.name))
  header.push('总分', '备注')
  const body = rangeRows.value.map((rangeRow) => {
    const excelRow: (string | number)[] = [rangeRow.rank, rangeRow.class.name, rangeRow.class.gradeLabel]
    const clsRecords = rangeRecords.value.filter((record) => record.class_id === rangeRow.class.id)
    catList.forEach((category) => {
      const categorySum = clsRecords
        .filter((record) => record.category === category.name)
        .reduce((sum, record) => sum + (Number(record.score) || 0), 0)
      excelRow.push(Math.round(categorySum * 100) / 100)
    })
    excelRow.push(rangeRow.total, rangeRow.remark || '')
    return excelRow
  })
  const wb = XLSX.utils.book_new()
  const ws = XLSX.utils.aoa_to_sheet([header, ...body])
  const colWidths: any[] = [{ wch: 6 }, { wch: 10 }, { wch: 10 }]
  catList.forEach(() => colWidths.push({ wch: 9 }))
  colWidths.push({ wch: 8 }, { wch: 20 })
  ws['!cols'] = colWidths
  XLSX.utils.book_append_sheet(wb, ws, '区间统计')
  XLSX.writeFile(wb, `班级检查扣分_${rangeStart}_${rangeEnd}_${Date.now()}.xlsx`)
  ElMessage.success('导出成功')
}

/**
 * 汇总某班某项目在自定义范围内的加减分合计。
 * @param classId 班级 id
 * @param catName 检查项目名称
 * @returns 加减分合计（保留两位小数）；该班此项目在范围内无记录时返回 null
 */
function sumByCat(classId: string, catName: string): number | null {
  const matchedRecords = rangeRecords.value.filter((record) => record.class_id === classId && record.category === catName)
  if (matchedRecords.length === 0) return null
  const matchedSum = matchedRecords.reduce((sum, record) => sum + (Number(record.score) || 0), 0)
  return Math.round(matchedSum * 100) / 100
}

/**
 * 区间内某班某项的「实际得分」：基础分 × 范围天数 + 加减分总和。
 * 若该班此项目在范围内无任何记录，则返回 null（不显示），避免误把基础分计入未发生的项。
 * @param classId 班级 id
 * @param catName 检查项目名称
 * @param baseScore 该项目的基础分
 * @returns 实际得分（保留两位小数）；范围内无记录时返回 null
 */
function sumByCatEffective(classId: string, catName: string, baseScore: number): number | null {
  const matchedRecords = rangeRecords.value.filter((record) => record.class_id === classId && record.category === catName)
  if (matchedRecords.length === 0) return null
  const adj = matchedRecords.reduce((sum, record) => sum + (Number(record.score) || 0), 0)
  return Math.round((baseScore * rangeDays.value + adj) * 100) / 100
}

/**
 * 分数展示格式化：null 显示为 '-'。
 * @param score 分数值，可为 null
 * @returns 展示用字符串
 */
function formatScore(score: number | null): string {
  return score === null ? '-' : String(score)
}

// ========== 管理检查项目 ==========
/**
 * 打开「管理检查项目」对话框，并复制一份副本用于编辑（按 sort_order 排序）。
 * 编辑期间的增删改只作用于副本，点「保存」才写库。
 * @returns 无返回值，直接控制弹窗与编辑态数据
 */
function openCatDialog() {
  // 复制一份用于编辑（按 sort_order）
  editingCats.value = categories.value
    .slice()
    .sort((a, b) => a.sort_order - b.sort_order)
    .map((category) => ({
      ...category,
      base_score: Number(category.base_score) || 0,
    }))
  newCatName.value = ''
  newCatBaseScore.value = 1
  catDialogVisible.value = true
}

/**
 * 在编辑态列表中追加一个新检查项目（排序号接在末尾）。
 * @returns 无返回值，直接修改编辑态列表并清空新增输入框
 */
function addNewCat() {
  const categoryName = newCatName.value.trim()
  if (!categoryName) {
    ElMessage.warning('请输入项目名称')
    return
  }
  if (editingCats.value.some((category) => category.name === categoryName)) {
    ElMessage.warning('已存在同名项目')
    return
  }
  const maxSortOrder = editingCats.value.reduce((max, category) => Math.max(max, category.sort_order), -1)
  editingCats.value.push({
    id: '',
    school_id: userStore.schoolId!,
    name: categoryName,
    base_score: Number(newCatBaseScore.value) || 0,
    sort_order: maxSortOrder + 1,
    is_active: true,
  })
  newCatName.value = ''
  newCatBaseScore.value = 1
}

/**
 * 从编辑态列表中移除指定位置的项目（仅改内存，保存后才落库）。
 * @param catIndex 项目在编辑态列表中的下标
 * @returns 无返回值
 */
function removeEditingCat(catIndex: number) {
  editingCats.value.splice(catIndex, 1)
}

/**
 * 在编辑态列表中上移/下移一个项目，并交换两者的 sort_order。
 * @param catIndex 项目在编辑态列表中的下标
 * @param dir 移动方向，-1 上移、1 下移
 * @returns 无返回值；越界时不做任何改动
 */
function moveCat(catIndex: number, dir: -1 | 1) {
  const targetIndex = catIndex + dir
  if (targetIndex < 0 || targetIndex >= editingCats.value.length) return
  const editableCategories = editingCats.value
  const currentCat = editableCategories[catIndex]
  const targetCat = editableCategories[targetIndex]
  // 交换 sort_order
  const currentSortOrder = currentCat.sort_order
  currentCat.sort_order = targetCat.sort_order
  targetCat.sort_order = currentSortOrder
  editableCategories[catIndex] = targetCat
  editableCategories[targetIndex] = currentCat
}

/**
 * 保存检查项目配置：先校验名称非空且不重复，再删除被移除的项目、按当前顺序 upsert 全部项目。
 * 保存后重新加载项目与当前页签的数据，使表格按新顺序渲染。
 * @returns 无返回值，成功后关闭弹窗
 */
async function saveCategories() {
  if (!userStore.schoolId) return
  // 校验重名
  const categoryNames = editingCats.value.map((category) => category.name.trim())
  if (categoryNames.some((categoryName) => !categoryName)) {
    ElMessage.warning('项目名称不能为空')
    return
  }
  const duplicatedName = categoryNames.find((categoryName, nameIndex) => categoryNames.indexOf(categoryName) !== nameIndex)
  if (duplicatedName) {
    ElMessage.warning(`项目名称重复：${duplicatedName}`)
    return
  }
  catSaving.value = true
  try {
    const currentIds = new Set(categories.value.map((category) => category.id))
    const editingIds = new Set(editingCats.value.filter((category) => category.id).map((category) => category.id))
    // 删除：原本存在但编辑后没了
    const toDelete = [...currentIds].filter((id) => !editingIds.has(id))
    // upsert：编辑后所有项
    const upserts = editingCats.value.map((category, orderIndex) => ({
      id: category.id || undefined,
      school_id: userStore.schoolId,
      name: category.name.trim(),
      base_score: Number(category.base_score) || 0,
      sort_order: orderIndex,
      is_active: true,
    }))
    if (toDelete.length > 0) {
      const { error } = await supabase
        .from('inspection_categories')
        .delete()
        .in('id', toDelete)
      if (error) throw error
    }
    if (upserts.length > 0) {
      const { error } = await supabase
        .from('inspection_categories')
        .upsert(upserts, { onConflict: 'school_id,name' })
      if (error) throw error
    }
    ElMessage.success('检查项目已保存')
    catDialogVisible.value = false
    await loadCategories()
    // 重新拉一遍数据，使表格按新顺序渲染
    if (activeTab.value === 'daily') await loadDayRecords()
    if (activeTab.value === 'weekly') await loadWeekRecords()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存失败')
  } finally {
    catSaving.value = false
  }
}

watch(selectedDate, () => {
  if (activeTab.value === 'daily') loadDayRecords()
})

watch(weekAnchorDate, () => {
  if (activeTab.value === 'weekly') loadWeekRecords()
})

watch(activeTab, (tabName) => {
  if (tabName === 'daily') loadDayRecords()
  if (tabName === 'weekly') loadWeekRecords()
})

onMounted(async () => {
  await loadClasses()
  await loadCategories()
  await nextTick()
  loadDayRecords()
})
</script>

<template>
  <div class="inspection-page">
    <el-tabs v-model="activeTab" type="border-card">
      <!-- ========== 按天登分 ========== -->
      <el-tab-pane label="按天登分" name="daily">
        <div class="toolbar">
          <div class="toolbar-left">
            <el-button :icon="ArrowLeft" circle size="small" @click="shiftDate(-1)" />
            <el-date-picker
              v-model="selectedDate"
              type="date"
              value-format="YYYY-MM-DD"
              placeholder="选择日期"
              style="width: 160px"
            />
            <el-button :icon="ArrowRight" circle size="small" @click="shiftDate(1)" />
            <span class="date-tip">
              填写各项目加减分（扣分为负、加分为正）；当日基础总分为
              <strong>{{ totalBaseScore }} 分</strong>，单元格显示「实际得分 = 基础分 ± 加减分」
            </span>
          </div>
          <div class="toolbar-right">
            <el-button :icon="Setting" @click="openCatDialog">管理检查项目</el-button>
            <el-button type="primary" :icon="DocumentChecked" :loading="saving" @click="saveDayScores">
              保存当天
            </el-button>
          </div>
        </div>

        <div class="table-scroll-x">
        <el-table
          :data="dayInputRows"
          v-loading="loading"
          border
          stripe
          size="small"
          :fit="false"
          style="width: 1380px"
        >
          <el-table-column type="index" label="序号" width="55" align="center" fixed="left" />
          <el-table-column prop="className" label="班级" width="100" align="center" fixed="left" />
          <el-table-column prop="gradeLabel" label="年级" width="80" align="center" fixed="left" />
          <el-table-column
            v-for="category in categories"
            :key="category.id"
            :label="`${category.name}(${category.base_score})`"
            align="center"
            width="100"
          >
            <template #default="{ row }">
              <div class="cell-stack">
                <el-input-number
                  :model-value="scoreInputValue(row as DayInputRow, category.name)"
                  :step="0.1"
                  :precision="1"
                  controls-position="right"
                  style="width: 90px"
                  size="small"
                  placeholder="加减分"
                  @update:model-value="onScoreInput(row as DayInputRow, category.name, $event)"
                />
                <div
                  class="cell-effective"
                  :class="dayScoreClass((row as DayInputRow).scores[category.name] ?? 0)"
                >
                  实得 {{ effectiveDayScore(row as DayInputRow, category.name) }}
                </div>
              </div>
            </template>
          </el-table-column>
          <el-table-column label="当日得分" width="100" align="center" fixed="right">
            <template #default="{ row }">
              <el-tag
                :type="
                  dayRowTotal(row as DayInputRow) >= totalBaseScore
                    ? 'success'
                    : 'warning'
                "
                effect="light"
              >
                {{ dayRowTotal(row as DayInputRow) }} / {{ totalBaseScore }}
              </el-tag>
            </template>
          </el-table-column>
          <el-table-column label="备注" align="center" width="140" fixed="right">
            <template #default="{ row }">
              <el-input v-model="row.remark" size="small" placeholder="选填" maxlength="50" />
            </template>
          </el-table-column>
        </el-table>
        </div>
      </el-tab-pane>

      <!-- ========== 按周统计 ========== -->
      <el-tab-pane label="按周统计" name="weekly">
        <div class="toolbar">
          <div class="toolbar-left">
            <el-button :icon="ArrowLeft" circle size="small" @click="shiftWeek(-7)" />
            <el-date-picker
              v-model="weekAnchorDate"
              type="date"
              value-format="YYYY-MM-DD"
              placeholder="选择周内任意一天"
              style="width: 160px"
            />
            <el-button :icon="ArrowRight" circle size="small" @click="shiftWeek(7)" />
            <span class="title-text">{{ weekTitle }}</span>
          </div>
          <div class="toolbar-right">
            <el-button :icon="Setting" @click="openCatDialog">管理检查项目</el-button>
            <el-button :icon="Download" @click="exportWeeklyExcel">导出 Excel</el-button>
          </div>
        </div>

        <el-table
          :data="weekMatrixRows"
          v-loading="loading"
          border
          stripe
          size="small"
          style="width: 100%"
        >
          <el-table-column type="index" label="序号" width="60" align="center" fixed="left" />
          <el-table-column prop="class.name" label="班级" width="90" align="center" fixed="left" />
          <el-table-column
            v-for="weekDay in weekDays"
            :key="weekDay.date"
            :label="weekDay.label"
            align="center"
          >
            <el-table-column
              v-for="category in categories"
              :key="category.id"
              :label="`${category.name}(${category.base_score})`"
              width="90"
              align="center"
            >
              <template #default="{ row }">
                <span :class="dayScoreClass(row.days[weekDay.date]?.[category.name])">
                  {{ effectiveWeekDayScore(row.days[weekDay.date]?.[category.name], category.name) ?? '-' }}
                </span>
              </template>
            </el-table-column>
          </el-table-column>
          <el-table-column
            prop="total"
            label="周总分"
            width="90"
            align="center"
            fixed="right"
          >
            <template #default="{ row }">
              <el-tag :type="row.total >= weekFullBaseScore ? 'success' : 'warning'" effect="light">
                {{ row.total }} / {{ weekFullBaseScore }}
              </el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="rank" label="名次" width="70" align="center" fixed="right" />
          <el-table-column
            prop="remark"
            label="备注"
            min-width="140"
            show-overflow-tooltip
            fixed="right"
          />
        </el-table>

        <div class="section-title">按年级排名</div>
        <el-table
          :data="gradeRankRows"
          v-loading="loading"
          border
          stripe
          size="small"
          style="width: 100%; max-width: 480px"
        >
          <el-table-column prop="grade" label="年级" width="100" align="center" />
          <el-table-column prop="rank" label="年级名次" width="90" align="center" />
          <el-table-column prop="className" label="班级" width="90" align="center" />
          <el-table-column prop="total" label="总分" width="90" align="center">
            <template #default="{ row }">
              <el-tag :type="row.total >= 0 ? 'success' : 'danger'" effect="light">
                {{ row.total }}
              </el-tag>
            </template>
          </el-table-column>
        </el-table>
      </el-tab-pane>

      <!-- ========== 自定义范围 ========== -->
      <el-tab-pane label="自定义范围" name="range">
        <div class="toolbar">
          <div class="toolbar-left">
            <el-date-picker
              v-model="rangeDates"
              type="daterange"
              range-separator="至"
              start-placeholder="开始日期"
              end-placeholder="结束日期"
              value-format="YYYY-MM-DD"
              style="width: 320px"
            />
            <el-button type="primary" :icon="Search" @click="loadRangeRecords">查询</el-button>
          </div>
          <div class="toolbar-right">
            <el-button :icon="Setting" @click="openCatDialog">管理检查项目</el-button>
            <el-button :icon="Download" :disabled="!rangeQueried" @click="exportRangeExcel">导出 Excel</el-button>
          </div>
        </div>

        <el-empty v-if="!rangeQueried" description="请选择起止日期后点击查询" :image-size="80" />
        <template v-else>
          <div class="section-title">全校排名</div>
          <el-table
            :data="rangeRows"
            v-loading="loading"
            border
            stripe
            size="small"
            style="width: 100%"
          >
            <el-table-column prop="rank" label="名次" width="70" align="center" fixed="left" />
            <el-table-column prop="class.name" label="班级" width="100" align="center" fixed="left" />
            <el-table-column prop="class.gradeLabel" label="年级" width="100" align="center" fixed="left" />
            <el-table-column
              v-for="category in categories"
              :key="category.id"
              :label="`${category.name}(${category.base_score * rangeDays})`"
              width="100"
              align="center"
            >
              <template #default="{ row }">
                <span :class="dayScoreClass(sumByCat(row.class.id, category.name))">
                  {{ formatScore(sumByCatEffective(row.class.id, category.name, category.base_score)) }}
                </span>
              </template>
            </el-table-column>
            <el-table-column
              prop="total"
              label="区间总分"
              width="120"
              align="center"
              fixed="right"
            >
              <template #default="{ row }">
                <el-tag
                  :type="row.total >= rangeFullBaseScore ? 'success' : 'warning'"
                  effect="light"
                >
                  {{ row.total }} / {{ rangeFullBaseScore }}
                </el-tag>
              </template>
            </el-table-column>
            <el-table-column
              prop="remark"
              label="备注"
              min-width="140"
              show-overflow-tooltip
              fixed="right"
            />
          </el-table>

          <div class="section-title">按年级排名</div>
          <el-table
            :data="rangeGradeRankRows"
            v-loading="loading"
            border
            stripe
            size="small"
            style="width: 100%; max-width: 520px"
          >
            <el-table-column prop="grade" label="年级" width="100" align="center" />
            <el-table-column prop="rank" label="年级名次" width="100" align="center" />
            <el-table-column prop="className" label="班级" width="100" align="center" />
            <el-table-column prop="total" label="总分" width="100" align="center">
              <template #default="{ row }">
                <el-tag :type="row.total >= 0 ? 'success' : 'danger'" effect="light">
                  {{ row.total }}
                </el-tag>
              </template>
            </el-table-column>
          </el-table>
        </template>
      </el-tab-pane>
    </el-tabs>

    <!-- ========== 管理检查项目对话框 ========== -->
    <el-dialog
      v-model="catDialogVisible"
      title="管理检查项目"
      width="560px"
      :close-on-click-modal="false"
      @close="catDialogVisible = false"
    >
      <div class="cat-dialog-tip">
        提示：项目名称用于按天登分/按周统计/区间统计/Excel 导出列头；删除已有项目不会删除历史扣分记录，但历史记录将不再纳入分类汇总。
      </div>

      <el-table :data="editingCats" border size="small" style="width: 100%">
        <el-table-column type="index" label="序号" width="60" align="center" />
        <el-table-column label="项目名称" min-width="160">
          <template #default="{ row }">
            <el-input v-model="row.name" size="small" placeholder="如：教室卫生" maxlength="20" />
          </template>
        </el-table-column>
        <el-table-column label="满分" width="120" align="center">
          <template #default="{ row }">
            <el-input-number
              v-model="row.base_score"
              :min="0"
              :max="10"
              :step="0.5"
              :precision="1"
              controls-position="right"
              size="small"
              style="width: 90px"
            />
          </template>
        </el-table-column>
        <el-table-column label="排序" width="180" align="center">
          <template #default="{ $index }">
            <el-button-group>
              <el-button :icon="ArrowUp" size="small" :disabled="$index === 0" @click="moveCat($index, -1)" />
              <el-button :icon="ArrowDown" size="small" :disabled="$index === editingCats.length - 1" @click="moveCat($index, 1)" />
            </el-button-group>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="80" align="center">
          <template #default="{ $index }">
            <el-button :icon="Delete" type="danger" size="small" link @click="removeEditingCat($index)" />
          </template>
        </el-table-column>
      </el-table>

      <div class="cat-add-row">
        <el-input
          v-model="newCatName"
          size="small"
          placeholder="新项目名称"
          maxlength="20"
          style="width: 240px"
          @keyup.enter="addNewCat"
        />
        <el-input-number
          v-model="newCatBaseScore"
          :min="0"
          :max="10"
          :step="0.5"
          :precision="1"
          controls-position="right"
          size="small"
          style="width: 120px"
          placeholder="满分"
        />
        <el-button type="primary" :icon="Plus" size="small" @click="addNewCat">新增</el-button>
      </div>

      <template #footer>
        <el-button @click="catDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="catSaving" @click="saveCategories">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script lang="ts">
// 该块仅用于兼容某些编辑器识别，保持空即可（函数都已在 <script setup> 内）
export default {}
</script>

<style scoped>
.inspection-page {
  padding: 0;
}

.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
  flex-wrap: wrap;
  gap: 12px;
}

.toolbar-left {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}

.toolbar-right {
  display: flex;
  align-items: center;
  gap: 8px;
}

.date-tip {
  font-size: 13px;
  color: #6b7280;
}

.title-text {
  font-size: 15px;
  font-weight: 600;
  color: #1f2937;
}

.section-title {
  margin: 20px 0 12px;
  font-size: 15px;
  font-weight: 600;
  color: #1f2937;
}

.score-neg {
  color: #ef4444;
  font-weight: 600;
}
.score-pos {
  color: #16a34a;
  font-weight: 600;
}

.cat-dialog-tip {
  font-size: 12px;
  color: #909399;
  margin-bottom: 12px;
  line-height: 1.5;
}

.cat-add-row {
  margin-top: 12px;
  display: flex;
  gap: 8px;
  align-items: center;
}

.cell-stack {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 4px 0;
}

.cell-effective {
  font-size: 12px;
  color: #6b7280;
  white-space: nowrap;
}

.table-scroll-x {
  width: 100%;
  overflow-x: auto;
}
</style>