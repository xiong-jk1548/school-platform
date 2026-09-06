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

async function loadData() {
  if (!userStore.classId) return
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('student_scores')
      .select('*')
      .order('exam_date', { ascending: false })
    if (error) throw error
    const rows = (data ?? []) as ScoreRow[]

    // 补齐 student_name
    const studentIds = Array.from(new Set(rows.map((r) => r.student_id)))
    if (studentIds.length > 0) {
      const { data: stuRes } = await supabase
        .from('students')
        .select('id, student_name')
        .in('id', studentIds)
      const stuMap: Record<string, string> = {}
      ;((stuRes ?? []) as any[]).forEach((s) => { stuMap[s.id] = s.student_name })
      rows.forEach((r) => { if (!r.student_name) r.student_name = stuMap[r.student_id] })
    }
    scores.value = rows

    // 考试列表
    const exams = Array.from(new Set(rows.map((r) => r.exam_name))).sort()
    examOptions.value = exams
    if (!currentExam.value && exams.length > 0) currentExam.value = exams[exams.length - 1]

    // 学科列表（取当前考试的学科）
    updateSubjectOptions()
  } catch (err: any) {
    ElMessage.error(err.message || '加载成绩数据失败')
  } finally {
    loading.value = false
  }
}

function updateSubjectOptions() {
  if (!currentExam.value) {
    subjectOptions.value = []
    currentSubject.value = ''
    return
  }
  const list = Array.from(
    new Set(scores.value.filter((r) => r.exam_name === currentExam.value).map((r) => r.subject)),
  ).sort()
  subjectOptions.value = list
  if (!currentSubject.value && list.length > 0) currentSubject.value = list[0]
}

// 当考试变化时，更新学科选项
import { watch } from 'vue'
watch(currentExam, updateSubjectOptions)

// ===== KPI 计算 =====
const examScores = computed(() =>
  scores.value.filter((r) => r.exam_name === currentExam.value),
)

const classAvg = computed(() => {
  if (examScores.value.length === 0) return 0
  const total = examScores.value.reduce((s, r) => s + r.score, 0)
  return +(total / examScores.value.length).toFixed(1)
})

const passRate = computed(() => {
  if (examScores.value.length === 0) return 0
  const passed = examScores.value.filter((r) => r.score / r.full_score >= toPct(passLineVal.value, r.full_score)).length
  return +((passed / examScores.value.length) * 100).toFixed(1)
})

const excellentRate = computed(() => {
  if (examScores.value.length === 0) return 0
  const excellent = examScores.value.filter((r) => r.score / r.full_score >= toPct(excellentLineVal.value, r.full_score)).length
  return +((excellent / examScores.value.length) * 100).toFixed(1)
})

const studentCount = computed(() => {
  if (!currentSubject.value) return 0
  return examScores.value.filter((r) => r.subject === currentSubject.value).length
})

// ===== 学科平均分柱状图数据 =====
const subjectAvgs = computed(() => {
  const map: Record<string, { sum: number; count: number }> = {}
  examScores.value.forEach((r) => {
    if (!map[r.subject]) map[r.subject] = { sum: 0, count: 0 }
    map[r.subject].sum += r.score
    map[r.subject].count += 1
  })
  const result = Object.entries(map).map(([subject, { sum, count }]) => ({
    subject,
    avg: +(sum / count).toFixed(1),
  }))
  // 找最大值用于柱状图归一化
  const max = Math.max(...result.map((r) => r.avg), 1)
  return result.map((r) => ({ ...r, pct: (r.avg / max) * 100 }))
})

// ===== 成绩分布（环形图数据）=====
const gradeDistribution = computed(() => {
  if (!currentSubject.value) return []
  const rows = examScores.value.filter((r) => r.subject === currentSubject.value)
  if (rows.length === 0) return []
  const total = rows.length
  const excellent = rows.filter((r) => r.score / r.full_score >= toPct(excellentLineVal.value, r.full_score)).length
  const good = rows.filter((r) => r.score / r.full_score >= GOOD_LINE && r.score / r.full_score < toPct(excellentLineVal.value, r.full_score)).length
  const pass = rows.filter((r) => r.score / r.full_score >= toPct(passLineVal.value, r.full_score) && r.score / r.full_score < GOOD_LINE).length
  const fail = rows.filter((r) => r.score / r.full_score < toPct(passLineVal.value, r.full_score)).length
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
  const map: Record<string, { sum: number; count: number }> = {}
  scores.value
    .filter((r) => r.subject === currentSubject.value)
    .forEach((r) => {
      if (!map[r.exam_name]) map[r.exam_name] = { sum: 0, count: 0 }
      map[r.exam_name].sum += r.score
      map[r.exam_name].count += 1
    })
  return Object.entries(map)
    .map(([exam_name, { sum, count }]) => ({ exam_name, avg: +(sum / count).toFixed(1) }))
    .sort((a, b) => {
      // 按考试日期排序（从原 scores 里找）
      const ra = scores.value.find((r) => r.exam_name === a.exam_name && r.subject === currentSubject.value)
      const rb = scores.value.find((r) => r.exam_name === b.exam_name && r.subject === currentSubject.value)
      return (ra?.exam_date || '').localeCompare(rb?.exam_date || '')
    })
})

// ===== 需关注学生 =====
const needAttention = computed(() => {
  if (!currentSubject.value) return []
  const rows = examScores.value.filter((r) => r.subject === currentSubject.value && r.score / r.full_score < toPct(passLineVal.value, r.full_score))
  return rows.sort((a, b) => a.score - b.score).slice(0, 5)
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
          <el-radio-button v-for="e in examOptions" :key="e" :label="e">{{ e }}</el-radio-button>
        </el-radio-group>
        <span class="switch-label" style="margin-left: 16px">学科：</span>
        <el-radio-group v-model="currentSubject" size="default">
          <el-radio-button v-for="s in subjectOptions" :key="s" :label="s">{{ s }}</el-radio-button>
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
                v-for="item in subjectAvgs"
                :key="item.subject"
                class="bar-item"
              >
                <div class="bar-label">{{ item.subject }}</div>
                <div class="bar-track">
                  <div class="bar-fill" :style="{ width: item.pct + '%' }">
                    <span class="bar-value">{{ item.avg }}</span>
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
                background: `conic-gradient(${gradeDistribution.map((g, i) =>
                  `${g.color} ${gradeDistribution.slice(0, i).reduce((s, x) => s + x.pct, 0)}% ${gradeDistribution.slice(0, i + 1).reduce((s, x) => s + x.pct, 0)}%`,
                ).join(', ')})`,
              }">
                <div class="ring-inner">
                  <div class="ring-center-num">{{ gradeDistribution[0]?.value + gradeDistribution[1]?.value + gradeDistribution[2]?.value || 0 }}</div>
                  <div class="ring-center-label">及格人数</div>
                </div>
              </div>
              <!-- 图例 -->
              <div class="ring-legend">
                <div v-for="g in gradeDistribution" :key="g.label" class="legend-item">
                  <span class="legend-dot" :style="{ background: g.color }"></span>
                  <span class="legend-label">{{ g.label }}</span>
                  <span class="legend-value">{{ g.value }} 人 · {{ g.pct }}%</span>
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
                <div v-for="i in 5" :key="i" class="grid-line"></div>
              </div>
              <svg class="trend-line" viewBox="0 0 400 150" preserveAspectRatio="none">
                <polyline
                  :points="trendData.map((d, i) => {
                    const x = (i / (trendData.length - 1)) * 400
                    const y = 150 - (d.avg / 100) * 150
                    return `${x},${y}`
                  }).join(' ')"
                  fill="none"
                  stroke="#2B5CE6"
                  stroke-width="3"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
                <circle
                  v-for="(d, i) in trendData"
                  :key="i"
                  :cx="(i / (trendData.length - 1)) * 400"
                  :cy="150 - (d.avg / 100) * 150"
                  r="6"
                  fill="#2B5CE6"
                  stroke="#fff"
                  stroke-width="2"
                />
              </svg>
              <div class="trend-x-labels">
                <span v-for="d in trendData" :key="d.exam_name">{{ d.exam_name }}</span>
              </div>
              <div class="trend-y-values">
                <span v-for="(d, i) in trendData" :key="i" class="y-val" :style="{ left: (i / (trendData.length - 1)) * 100 + '%' }">{{ d.avg }}</span>
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
              <div v-for="row in needAttention" :key="row.id" class="attention-item">
                <div class="attention-avatar">
                  {{ (row.student_name || '?').charAt(0) }}
                </div>
                <div class="attention-info">
                  <div class="attention-name">{{ row.student_name }}</div>
                  <div class="attention-sub">分数 {{ row.score }} / {{ row.full_score }}（{{ ((row.score / row.full_score) * 100).toFixed(1) }}%）</div>
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
