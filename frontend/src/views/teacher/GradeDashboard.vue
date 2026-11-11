<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { ElMessage } from 'element-plus'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()

// 分数阈值（与 GradeManage 共用 localStorage，支持双模式）
const lineMode = ref<'percent' | 'score'>(localStorage.getItem('MOCK_LINE_MODE') === 'score' ? 'score' : 'percent')
const excellentLineVal = ref(parseFloat(localStorage.getItem('MOCK_EXCELLENT_LINE') || (lineMode.value === 'score' ? '85' : '0.85')) || (lineMode.value === 'score' ? 85 : 0.85))
const passLineVal = ref(parseFloat(localStorage.getItem('MOCK_PASS_LINE') || (lineMode.value === 'score' ? '60' : '0.60')) || (lineMode.value === 'score' ? 60 : 0.60))
const GOOD_LINE = 0.70 // 良好线固定百分比
function toPct(lineVal: number, fullScore: number): number {
  if (lineMode.value === 'percent') return lineVal
  return fullScore > 0 ? lineVal / fullScore : 0
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

const scores = ref<ScoreRow[]>([])
const loading = ref(false)

// 考试切换
const examOptions = ref<string[]>([])
const currentExam = ref('')
const subjectOptions = ref<string[]>([])
const currentSubject = ref('')

/**
 * 加载本班所有成绩记录，补齐学生姓名，并初始化考试/学科下拉数据源
 * @returns 无返回值（副作用：写入 scores、examOptions、subjectOptions，并维护 loading）
 */
async function loadData() {
  if (!userStore.classId) return
  loading.value = true
  try {
    const { data: scoreRows, error } = await supabase
      .from('student_scores')
      .select('*')
      .order('exam_date', { ascending: false })
    if (error) throw error
    const scoreList = (scoreRows ?? []) as ScoreRow[]

    // 补齐 student_name
    const studentIds = Array.from(new Set(scoreList.map((score) => score.student_id)))
    if (studentIds.length > 0) {
      const { data: studentRows } = await supabase
        .from('students')
        .select('id, student_name')
        .in('id', studentIds)
      const stuMap: Record<string, string> = {}
      ;((studentRows ?? []) as any[]).forEach((student) => { stuMap[student.id] = student.student_name })
      scoreList.forEach((score) => { if (!score.student_name) score.student_name = stuMap[score.student_id] })
    }
    scores.value = scoreList

    // 考试列表
    const examNames = Array.from(new Set(scoreList.map((score) => score.exam_name))).sort()
    examOptions.value = examNames
    if (!currentExam.value && examNames.length > 0) currentExam.value = examNames[examNames.length - 1]

    // 学科列表（取当前考试的学科）
    updateSubjectOptions()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载成绩数据失败')
  } finally {
    loading.value = false
  }
}

/**
 * 按当前选中的考试刷新学科下拉；当前学科为空时默认选中第一个学科
 */
function updateSubjectOptions() {
  if (!currentExam.value) {
    subjectOptions.value = []
    currentSubject.value = ''
    return
  }
  const subjectList = Array.from(
    new Set(scores.value.filter((score) => score.exam_name === currentExam.value).map((score) => score.subject)),
  ).sort()
  subjectOptions.value = subjectList
  if (!currentSubject.value && subjectList.length > 0) currentSubject.value = subjectList[0]
}

// 当考试变化时，更新学科选项
import { watch } from 'vue'
watch(currentExam, updateSubjectOptions)

// ===== KPI 计算 =====
const examScores = computed(() =>
  scores.value.filter((score) => score.exam_name === currentExam.value),
)

const classAvg = computed(() => {
  if (examScores.value.length === 0) return 0
  const totalScore = examScores.value.reduce((sum, score) => sum + score.score, 0)
  return +(totalScore / examScores.value.length).toFixed(1)
})

const passRate = computed(() => {
  if (examScores.value.length === 0) return 0
  const passed = examScores.value.filter((score) => score.score / score.full_score >= toPct(passLineVal.value, score.full_score)).length
  return +((passed / examScores.value.length) * 100).toFixed(1)
})

const excellentRate = computed(() => {
  if (examScores.value.length === 0) return 0
  const excellent = examScores.value.filter((score) => score.score / score.full_score >= toPct(excellentLineVal.value, score.full_score)).length
  return +((excellent / examScores.value.length) * 100).toFixed(1)
})

const studentCount = computed(() => {
  if (!currentSubject.value) return 0
  return examScores.value.filter((score) => score.subject === currentSubject.value).length
})

// ===== 学科平均分柱状图数据 =====
const subjectAvgs = computed(() => {
  const statsBySubject: Record<string, { sum: number; count: number }> = {}
  examScores.value.forEach((score) => {
    if (!statsBySubject[score.subject]) statsBySubject[score.subject] = { sum: 0, count: 0 }
    statsBySubject[score.subject].sum += score.score
    statsBySubject[score.subject].count += 1
  })
  const subjectAvgRows = Object.entries(statsBySubject).map(([subject, { sum, count }]) => ({
    subject,
    avg: +(sum / count).toFixed(1),
  }))
  // 找最大值用于柱状图归一化
  const maxAvg = Math.max(...subjectAvgRows.map((avgRow) => avgRow.avg), 1)
  return subjectAvgRows.map((avgRow) => ({ ...avgRow, pct: (avgRow.avg / maxAvg) * 100 }))
})

// ===== 成绩分布（环形图数据）=====
const gradeDistribution = computed(() => {
  if (!currentSubject.value) return []
  const subjectScores = examScores.value.filter((score) => score.subject === currentSubject.value)
  if (subjectScores.length === 0) return []
  const total = subjectScores.length
  const excellent = subjectScores.filter((score) => score.score / score.full_score >= toPct(excellentLineVal.value, score.full_score)).length
  const good = subjectScores.filter((score) => score.score / score.full_score >= GOOD_LINE && score.score / score.full_score < toPct(excellentLineVal.value, score.full_score)).length
  const pass = subjectScores.filter((score) => score.score / score.full_score >= toPct(passLineVal.value, score.full_score) && score.score / score.full_score < GOOD_LINE).length
  const fail = subjectScores.filter((score) => score.score / score.full_score < toPct(passLineVal.value, score.full_score)).length
  const exL = Math.round(toPct(excellentLineVal.value, 100) * 100)
  const psL = Math.round(toPct(passLineVal.value, 100) * 100)
  const gdL = Math.round(GOOD_LINE * 100)
  return [
    { label: `优秀(≥${exL}%)`, value: excellent, pct: +((excellent / total) * 100).toFixed(1), color: '#2B5CE6' },
    { label: `良好(${gdL}-${exL}%)`, value: good, pct: +((good / total) * 100).toFixed(1), color: '#F59E0B' },
    { label: `及格(${psL}-${gdL}%)`, value: pass, pct: +((pass / total) * 100).toFixed(1), color: '#10B981' },
    { label: `不及格(<${psL}%)`, value: fail, pct: +((fail / total) * 100).toFixed(1), color: '#EF4444' },
  ]
})

// ===== 趋势折线（同一学科，不同考试）=====
const trendData = computed(() => {
  if (!currentSubject.value) return []
  const statsByExam: Record<string, { sum: number; count: number }> = {}
  scores.value
    .filter((score) => score.subject === currentSubject.value)
    .forEach((score) => {
      if (!statsByExam[score.exam_name]) statsByExam[score.exam_name] = { sum: 0, count: 0 }
      statsByExam[score.exam_name].sum += score.score
      statsByExam[score.exam_name].count += 1
    })
  return Object.entries(statsByExam)
    .map(([exam_name, { sum, count }]) => ({ exam_name, avg: +(sum / count).toFixed(1) }))
    .sort((examA, examB) => {
      // 按考试日期排序（从原 scores 里找）
      const scoreOfA = scores.value.find((score) => score.exam_name === examA.exam_name && score.subject === currentSubject.value)
      const scoreOfB = scores.value.find((score) => score.exam_name === examB.exam_name && score.subject === currentSubject.value)
      return (scoreOfA?.exam_date || '').localeCompare(scoreOfB?.exam_date || '')
    })
})

// ===== 需关注学生 =====
const needAttention = computed(() => {
  if (!currentSubject.value) return []
  const failingScores = examScores.value.filter((score) => score.subject === currentSubject.value && score.score / score.full_score < toPct(passLineVal.value, score.full_score))
  return failingScores.sort((scoreA, scoreB) => scoreA.score - scoreB.score).slice(0, 5)
})

onMounted(loadData)
</script>

<template>
  <div class="grade-dashboard">
    <!-- 顶部：考试/学科切换器 -->
    <div class="toolbar">
      <div class="toolbar-left">
        <span class="toolbar-title">{{ userStore.className || '本班' }} · 成绩仪表盘</span>
      </div>
      <div class="toolbar-right">
        <span class="switch-label">考试：</span>
        <el-radio-group v-model="currentExam" size="default" @change="updateSubjectOptions">
          <el-radio-button v-for="exam in examOptions" :key="exam" :label="exam">{{ exam }}</el-radio-button>
        </el-radio-group>
        <span class="switch-label" style="margin-left: 16px">学科：</span>
        <el-radio-group v-model="currentSubject" size="default">
          <el-radio-button v-for="subject in subjectOptions" :key="subject" :label="subject">{{ subject }}</el-radio-button>
        </el-radio-group>
      </div>
    </div>

    <div v-if="loading" class="loading-hint">加载中...</div>
    <div v-else-if="examScores.length === 0" class="empty-hint">
      暂无成绩数据，请先在「成绩管理」中录入成绩
    </div>
    <template v-else>
      <!-- KPI 卡片区 -->
      <el-row :gutter="16" class="kpi-row">
        <el-col :xs="12" :sm="6">
          <div class="kpi-card">
            <div class="kpi-label">班级平均分</div>
            <div class="hero-number">{{ classAvg }}</div>
            <div class="kpi-trend up">
              <span>满分 100</span>
            </div>
          </div>
        </el-col>
        <el-col :xs="12" :sm="6">
          <div class="kpi-card">
            <div class="kpi-label">及格率</div>
            <div class="hero-number green">{{ passRate }}%</div>
            <div class="kpi-trend" :class="passRate >= 90 ? 'up' : 'down'">
              <span>{{ passRate >= 90 ? '表现优秀' : '需关注' }}</span>
            </div>
          </div>
        </el-col>
        <el-col :xs="12" :sm="6">
          <div class="kpi-card">
            <div class="kpi-label">优秀率</div>
            <div class="hero-number warm">{{ excellentRate }}%</div>
            <div class="kpi-trend">
              <span>优秀线 ≥{{ Math.round(toPct(excellentLineVal, 100) * 100) }}%</span>
            </div>
          </div>
        </el-col>
        <el-col :xs="12" :sm="6">
          <div class="kpi-card">
            <div class="kpi-label">参考人数</div>
            <div class="hero-number">{{ studentCount }}</div>
            <div class="kpi-trend">
              <span>当前学科</span>
            </div>
          </div>
        </el-col>
      </el-row>

      <!-- 图表区 -->
      <el-row :gutter="16" class="chart-row">
        <el-col :xs="24" :sm="14">
          <div class="dashboard-card">
            <div class="dashboard-card-title">各学科平均分对比</div>
            <div class="bar-chart">
              <div
                v-for="subjectAvg in subjectAvgs"
                :key="subjectAvg.subject"
                class="bar-item"
              >
                <div class="bar-label">{{ subjectAvg.subject }}</div>
                <div class="bar-track">
                  <div class="bar-fill" :style="{ width: subjectAvg.pct + '%' }">
                    <span class="bar-value">{{ subjectAvg.avg }}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </el-col>
        <el-col :xs="24" :sm="10">
          <div class="dashboard-card">
            <div class="dashboard-card-title">成绩等级分布（{{ currentSubject || '-' }}）</div>
            <div class="grade-dist" v-if="gradeDistribution.length > 0">
              <!-- 环形图（纯 CSS conic-gradient） -->
              <div class="ring-chart" :style="{
                background: `conic-gradient(${gradeDistribution.map((grade, gradeIdx) =>
                  `${grade.color} ${gradeDistribution.slice(0, gradeIdx).reduce((sumPct, prevGrade) => sumPct + prevGrade.pct, 0)}% ${gradeDistribution.slice(0, gradeIdx + 1).reduce((sumPct, prevGrade) => sumPct + prevGrade.pct, 0)}%`,
                ).join(', ')})`,
              }">
                <div class="ring-inner">
                  <div class="ring-center-num">{{ gradeDistribution[0]?.value + gradeDistribution[1]?.value + gradeDistribution[2]?.value || 0 }}</div>
                  <div class="ring-center-label">及格人数</div>
                </div>
              </div>
              <!-- 图例 -->
              <div class="ring-legend">
                <div v-for="grade in gradeDistribution" :key="grade.label" class="legend-item">
                  <span class="legend-dot" :style="{ background: grade.color }"></span>
                  <span class="legend-label">{{ grade.label }}</span>
                  <span class="legend-value">{{ grade.value }} 人 · {{ grade.pct }}%</span>
                </div>
              </div>
            </div>
            <div v-else class="empty-mini">请选择学科</div>
          </div>
        </el-col>
      </el-row>

      <el-row :gutter="16" class="chart-row">
        <el-col :xs="24" :sm="14">
          <div class="dashboard-card">
            <div class="dashboard-card-title">
              {{ currentSubject || '-' }} 成绩趋势
            </div>
            <div class="trend-chart" v-if="trendData.length >= 2">
              <div class="trend-grid">
                <div v-for="gridLineNo in 5" :key="gridLineNo" class="grid-line"></div>
              </div>
              <svg class="trend-line" viewBox="0 0 400 150" preserveAspectRatio="none">
                <polyline
                  :points="trendData.map((point, pointIdx) => {
                    const x = (pointIdx / (trendData.length - 1)) * 400
                    const y = 150 - (point.avg / 100) * 150
                    return `${x},${y}`
                  }).join(' ')"
                  fill="none"
                  stroke="#2B5CE6"
                  stroke-width="3"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
                <circle
                  v-for="(point, pointIdx) in trendData"
                  :key="pointIdx"
                  :cx="(pointIdx / (trendData.length - 1)) * 400"
                  :cy="150 - (point.avg / 100) * 150"
                  r="6"
                  fill="#2B5CE6"
                  stroke="#fff"
                  stroke-width="2"
                />
              </svg>
              <div class="trend-x-labels">
                <span v-for="point in trendData" :key="point.exam_name">{{ point.exam_name }}</span>
              </div>
              <div class="trend-y-values">
                <span v-for="(point, pointIdx) in trendData" :key="pointIdx" class="y-val" :style="{ left: (pointIdx / (trendData.length - 1)) * 100 + '%' }">{{ point.avg }}</span>
              </div>
            </div>
            <div v-else class="empty-mini">至少需要 2 次考试成绩才能显示趋势</div>
          </div>
        </el-col>
        <el-col :xs="24" :sm="10">
          <div class="dashboard-card">
            <div class="dashboard-card-title">
              需关注学生（{{ currentSubject || '-' }}）
            </div>
            <div v-if="needAttention.length > 0" class="attention-list">
              <div v-for="failingScore in needAttention" :key="failingScore.id" class="attention-item">
                <div class="attention-avatar">
                  {{ (failingScore.student_name || '?').charAt(0) }}
                </div>
                <div class="attention-info">
                  <div class="attention-name">{{ failingScore.student_name }}</div>
                  <div class="attention-sub">分数 {{ failingScore.score }} / {{ failingScore.full_score }}（{{ ((failingScore.score / failingScore.full_score) * 100).toFixed(1) }}%）</div>
                </div>
                <el-tag type="danger" effect="plain" size="small">不及格</el-tag>
              </div>
            </div>
            <div v-else class="empty-mini">👍 当前学科暂无不及格学生</div>
          </div>
        </el-col>
      </el-row>
    </template>
  </div>
</template>

<style scoped>
.grade-dashboard {
  padding: 0;
}
.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: 12px;
  margin-bottom: 20px;
  padding: 16px 20px;
  background: linear-gradient(135deg, #1E3A8A 0%, #2B5CE6 100%);
  border-radius: 12px;
  color: #fff;
  box-shadow: 0 4px 16px rgba(30, 58, 138, 0.2);
}
.toolbar-left {
  display: flex;
  align-items: center;
  gap: 10px;
}
.toolbar-icon {
  font-size: 22px;
}
.toolbar-title {
  font-size: 18px;
  font-weight: 600;
}
.toolbar-right {
  display: flex;
  align-items: center;
}
.switch-label {
  font-size: 13px;
  opacity: 0.9;
  margin-right: 6px;
}
.toolbar-right :deep(.el-radio-button__inner) {
  background: rgba(255, 255, 255, 0.15);
  border-color: rgba(255, 255, 255, 0.25);
  color: #fff;
}
.toolbar-right :deep(.el-radio-button__original-radio:checked + .el-radio-button__inner) {
  background: #fff;
  color: #2B5CE6;
  border-color: #fff;
}

.kpi-row {
  margin-bottom: 16px;
}
.chart-row {
  margin-bottom: 16px;
}
.loading-hint,
.empty-hint {
  text-align: center;
  padding: 60px 20px;
  color: #6B7280;
  background: #fff;
  border-radius: 12px;
  border: 1px solid #E5E9F0;
}
.empty-mini {
  text-align: center;
  padding: 40px 20px;
  color: #9CA3AF;
  font-size: 14px;
}

/* 柱状图 */
.bar-chart {
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding-top: 8px;
}
.bar-item {
  display: flex;
  align-items: center;
  gap: 12px;
}
.bar-label {
  width: 70px;
  font-size: 14px;
  color: #1F2937;
  font-weight: 500;
  text-align: right;
}
.bar-track {
  flex: 1;
  height: 28px;
  background: #F0F4FA;
  border-radius: 6px;
  overflow: hidden;
  position: relative;
}
.bar-fill {
  height: 100%;
  background: linear-gradient(90deg, #2B5CE6, #4D7BED);
  border-radius: 6px;
  transition: width 0.4s ease;
  display: flex;
  align-items: center;
  padding-left: 10px;
  min-width: 40px;
}
.bar-value {
  font-size: 14px;
  font-weight: 700;
  color: #fff;
  font-variant-numeric: tabular-nums;
}

/* 环形图 */
.grade-dist {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 20px;
  padding-top: 8px;
}
.ring-chart {
  width: 140px;
  height: 140px;
  border-radius: 50%;
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
}
.ring-inner {
  width: 92px;
  height: 92px;
  border-radius: 50%;
  background: #fff;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  box-shadow: inset 0 0 0 1px #E5E9F0;
}
.ring-center-num {
  font-size: 24px;
  font-weight: 700;
  color: #2B5CE6;
  font-variant-numeric: tabular-nums;
}
.ring-center-label {
  font-size: 11px;
  color: #6B7280;
  margin-top: 2px;
}
.ring-legend {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.legend-item {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
}
.legend-dot {
  width: 10px;
  height: 10px;
  border-radius: 3px;
  flex-shrink: 0;
}
.legend-label {
  flex: 1;
  color: #4B5563;
}
.legend-value {
  color: #1F2937;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

/* 趋势折线 */
.trend-chart {
  position: relative;
  height: 180px;
  padding-top: 10px;
}
.trend-grid {
  position: absolute;
  top: 10px;
  left: 0;
  right: 0;
  bottom: 30px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}
.grid-line {
  height: 1px;
  background: #EEF1F6;
}
.trend-line {
  position: absolute;
  top: 10px;
  left: 0;
  right: 0;
  bottom: 30px;
  width: 100%;
  height: calc(100% - 40px);
}
.trend-x-labels {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  display: flex;
  justify-content: space-between;
  font-size: 12px;
  color: #6B7280;
  padding: 0 4px;
}
.trend-y-values {
  position: absolute;
  top: -4px;
  left: 0;
  right: 0;
  height: 16px;
}
.y-val {
  position: absolute;
  transform: translateX(-50%);
  font-size: 11px;
  font-weight: 600;
  color: #2B5CE6;
  background: #fff;
  padding: 0 4px;
}

/* 关注列表 */
.attention-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.attention-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  background: #FFF8F0;
  border: 1px solid #FFE0B2;
  border-radius: 10px;
  transition: background 0.2s;
}
.attention-item:hover {
  background: #FFF0DC;
}
.attention-avatar {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: #EF4444;
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 15px;
  flex-shrink: 0;
}
.attention-info {
  flex: 1;
  min-width: 0;
}
.attention-name {
  font-size: 14px;
  font-weight: 600;
  color: #1F2937;
}
.attention-sub {
  font-size: 12px;
  color: #6B7280;
  margin-top: 2px;
}
</style>
