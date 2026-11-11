<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useUserStore } from '@/stores/user'
import { supabase } from '@/api/supabase'
import { Files, User, Avatar, TrendCharts, OfficeBuilding } from '@element-plus/icons-vue'

const userStore = useUserStore()

/** 数据大屏顶部四项指标：班级数、教师数、学生数、本月积分净变动 */
const summary = ref({
  classCount: 0,
  teacherCount: 0,
  studentCount: 0,
  monthChange: 0,
})

/** 各班级积分对比（柱状图数据，按总积分从高到低；pct 为按最大值归一化后的宽度百分比） */
const classScoreRows = ref<
  { class_id: string; class_name: string; total_score: number; pct: number }[]
>([])

/** 近 7 天每日积分净变动（折线图数据；y 为 viewBox 0~150 内的纵坐标） */
const dailyTrend = ref<{ dayLabel: string; change: number; y: number }[]>([])

const loading = ref(false)
/** 无法取到学校信息或查询失败时的提示语，为空表示正常展示图表 */
const hint = ref('')

/** 趋势图统计天数（含今天） */
const TREND_DAY_COUNT = 7
/** 折线图绘图区高度，与模板里的 viewBox 高度一致 */
const TREND_VIEWBOX_HEIGHT = 150
/** 零轴纵坐标：取绘图区中线，净加分为正画在上方、净减分画在下方 */
const TREND_ZERO_Y = TREND_VIEWBOX_HEIGHT / 2
/** 折线纵向振幅，上下各留出 15 的边距，避免顶点贴到边框 */
const TREND_AMPLITUDE = TREND_ZERO_Y - 15

/**
 * 把月份或日期补成两位数字，供拼接日期键使用。
 * @param value 月份（1~12）或日期（1~31）
 * @returns 两位数字字符串，例如 3 → '03'
 */
function pad2(value: number): string {
  return String(value).padStart(2, '0')
}

/**
 * 把数据库里的时间字符串转成本地时区的 YYYY-MM-DD，用于按天分组。
 * 不直接截取 ISO 字符串前 10 位——那样在 UTC 与本地日期跨天时会把流水算到前一天。
 * @param timestamp 数据库时间列的值（ISO 字符串）
 * @returns 本地日期键，例如 '2026-09-20'
 */
function toLocalDayKey(timestamp: string): string {
  const at = new Date(timestamp)
  return `${at.getFullYear()}-${pad2(at.getMonth() + 1)}-${pad2(at.getDate())}`
}

/**
 * 汇总各班级的学生总积分，按从高到低排序并归一化出柱状图宽度。
 * @param classList classes 表本校班级行（含 class_name 与兼容列 name）
 * @param studentList students 表本校学生行（含 class_id 与 total_score）
 * @returns 无（副作用：写入 classScoreRows）
 */
function buildClassScoreChart(classList: any[], studentList: any[]): void {
  const scoreByClass: Record<string, number> = {}
  for (const student of studentList) {
    if (!student.class_id) continue
    scoreByClass[student.class_id] =
      (scoreByClass[student.class_id] ?? 0) + (Number(student.total_score) || 0)
  }

  const rows = classList.map((classRow) => ({
    class_id: classRow.id,
    class_name: classRow.class_name ?? classRow.name ?? '未命名班级',
    total_score: scoreByClass[classRow.id] ?? 0,
  }))
  rows.sort((classA, classB) => classB.total_score - classA.total_score)

  // 按绝对值最大的班级归一化，否则积分高的班会把其它班压成一条细线
  const maxAbsScore = Math.max(...rows.map((row) => Math.abs(row.total_score)), 1)
  classScoreRows.value = rows.map((row) => ({
    ...row,
    pct: (Math.abs(row.total_score) / maxAbsScore) * 100,
  }))
}

/**
 * 把查询窗口内的积分流水按天汇总成净变动，并算出折线坐标。
 * @param scoreLogList score_log 表查询窗口内的流水行（含 score 与 created_at）
 * @param now 计算 7 天窗口的基准时间，与查询时保持同一天，避免跨零点错位
 * @returns 无（副作用：写入 dailyTrend）
 */
function buildDailyTrendChart(scoreLogList: any[], now: Date): void {
  const changeByDay: Record<string, number> = {}
  for (const scoreLog of scoreLogList) {
    if (!scoreLog.created_at) continue
    const dayKey = toLocalDayKey(scoreLog.created_at)
    changeByDay[dayKey] = (changeByDay[dayKey] ?? 0) + (Number(scoreLog.score) || 0)
  }

  const daySlots: { dayLabel: string; change: number }[] = []
  for (let offset = TREND_DAY_COUNT - 1; offset >= 0; offset--) {
    const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset)
    const dayKey = `${day.getFullYear()}-${pad2(day.getMonth() + 1)}-${pad2(day.getDate())}`
    daySlots.push({
      dayLabel: `${day.getMonth() + 1}/${day.getDate()}`,
      change: changeByDay[dayKey] ?? 0,
    })
  }

  const maxAbsChange = Math.max(...daySlots.map((slot) => Math.abs(slot.change)), 1)
  dailyTrend.value = daySlots.map((slot) => ({
    ...slot,
    y: TREND_ZERO_Y - (slot.change / maxAbsChange) * TREND_AMPLITUDE,
  }))
}

/**
 * 加载本校数据大屏：顶部四项指标、各班级积分对比、近 7 天积分净变动。
 * 本月统计与趋势图共用一次流水查询——月初时 7 天窗口会跨到上个月，
 * 若分两次查，按月份筛选会把趋势图前几天的数据截掉。
 * @returns Promise<void>；查不到学校信息或查询报错时写入 hint，不抛异常
 */
async function loadDashboard(): Promise<void> {
  const schoolId = userStore.schoolId
  if (!schoolId) {
    hint.value = '未获取到学校信息，请退出后重新登录'
    return
  }

  loading.value = true
  try {
    const now = new Date()
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1)
    const trendStart = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate() - (TREND_DAY_COUNT - 1),
    )
    const windowStart = monthStart < trendStart ? monthStart : trendStart

    const [
      { data: classRows, error: classQueryError },
      { count: teacherTotal, error: teacherQueryError },
      { data: studentRows, error: studentQueryError },
      { data: scoreLogRows, error: logQueryError },
    ] = await Promise.all([
      supabase.from('classes').select('id, class_name, name').eq('school_id', schoolId),
      // 学校管理员同时也是本校教师，统计教师数时须一并计入（与「教师管理」列表口径一致）
      supabase
        .from('profiles')
        .select('*', { count: 'exact', head: true })
        .eq('school_id', schoolId)
        .in('role', ['teacher', 'school_admin']),
      supabase.from('students').select('id, class_id, total_score').eq('school_id', schoolId),
      supabase
        .from('score_log')
        .select('score, created_at')
        .eq('school_id', schoolId)
        .gte('created_at', windowStart.toISOString()),
    ])
    if (classQueryError) throw classQueryError
    if (teacherQueryError) throw teacherQueryError
    if (studentQueryError) throw studentQueryError
    if (logQueryError) throw logQueryError

    const classList = (classRows ?? []) as any[]
    const studentList = (studentRows ?? []) as any[]
    const scoreLogList = (scoreLogRows ?? []) as any[]

    let monthChange = 0
    for (const scoreLog of scoreLogList) {
      if (!scoreLog.created_at) continue
      if (new Date(scoreLog.created_at) >= monthStart) {
        monthChange += Number(scoreLog.score) || 0
      }
    }

    summary.value = {
      classCount: classList.length,
      teacherCount: teacherTotal ?? 0,
      studentCount: studentList.length,
      monthChange,
    }
    buildClassScoreChart(classList, studentList)
    buildDailyTrendChart(scoreLogList, now)
  } catch (err: unknown) {
    hint.value = err instanceof Error && err.message ? err.message : '加载工作台数据失败'
  } finally {
    loading.value = false
  }
}

onMounted(loadDashboard)
</script>

<template>
  <div class="page" v-loading="loading">
    <el-card shadow="never" class="welcome-card">
      <div class="welcome-inner">
        <div>
          <div class="welcome-greeting">
            您好，{{ userStore.name ?? userStore.email ?? '学校管理员' }}
          </div>
          <div class="welcome-sub">
            {{ userStore.schoolName ?? '本校' }} · 数据总览
          </div>
        </div>
        <el-icon :size="48"><OfficeBuilding /></el-icon>
      </div>
    </el-card>

    <el-alert v-if="hint" :title="hint" type="warning" show-icon :closable="false" />

    <div class="stat-row">
      <div class="stat-item">
        <div class="stat-icon" style="background: #eaf3ff; color: #1e6fd9">
          <el-icon :size="24"><Files /></el-icon>
        </div>
        <div class="stat-detail">
          <div class="stat-num">{{ summary.classCount }}</div>
          <div class="stat-label">班级数</div>
        </div>
      </div>
      <div class="stat-item">
        <div class="stat-icon" style="background: #f3e8ff; color: #722ed1">
          <el-icon :size="24"><User /></el-icon>
        </div>
        <div class="stat-detail">
          <div class="stat-num">{{ summary.teacherCount }}</div>
          <div class="stat-label">教师数</div>
        </div>
      </div>
      <div class="stat-item">
        <div class="stat-icon" style="background: #e6fffb; color: #13c2c2">
          <el-icon :size="24"><Avatar /></el-icon>
        </div>
        <div class="stat-detail">
          <div class="stat-num">{{ summary.studentCount }}</div>
          <div class="stat-label">学生数</div>
        </div>
      </div>
      <div class="stat-item">
        <div class="stat-icon" style="background: #fff7e6; color: #fa8c16">
          <el-icon :size="24"><TrendCharts /></el-icon>
        </div>
        <div class="stat-detail">
          <div class="stat-num" :class="summary.monthChange < 0 ? 'num-sub' : 'num-add'">
            {{ summary.monthChange > 0 ? '+' : '' }}{{ summary.monthChange }}
          </div>
          <div class="stat-label">本月积分变动</div>
        </div>
      </div>
    </div>

    <el-row :gutter="16">
      <el-col :xs="24" :sm="12">
        <div class="dashboard-card">
          <div class="dashboard-card-title">
            各班级积分对比
            <span class="card-sub">共 {{ classScoreRows.length }} 个班级</span>
          </div>
          <div v-if="classScoreRows.length > 0" class="bar-chart">
            <div v-for="classScore in classScoreRows" :key="classScore.class_id" class="bar-item">
              <div class="bar-label" :title="classScore.class_name">
                {{ classScore.class_name }}
              </div>
              <div class="bar-track">
                <div class="bar-fill" :style="{ width: classScore.pct + '%' }">
                  <span class="bar-value">{{ classScore.total_score }}</span>
                </div>
              </div>
            </div>
          </div>
          <div v-else class="empty-mini">暂无班级数据</div>
        </div>
      </el-col>

      <el-col :xs="24" :sm="12">
        <div class="dashboard-card">
          <div class="dashboard-card-title">
            近 {{ TREND_DAY_COUNT }} 天积分变动
            <span class="card-sub">含加分为正、扣分为负</span>
          </div>
          <div class="trend-chart">
            <div class="trend-grid">
              <div v-for="gridLineNo in 5" :key="gridLineNo" class="grid-line"></div>
            </div>
            <svg
              class="trend-line"
              :viewBox="`0 0 400 ${TREND_VIEWBOX_HEIGHT}`"
              preserveAspectRatio="none"
            >
              <line
                x1="0"
                :y1="TREND_ZERO_Y"
                x2="400"
                :y2="TREND_ZERO_Y"
                stroke="#D9E2F0"
                stroke-width="1"
                stroke-dasharray="4 4"
              />
              <polyline
                :points="
                  dailyTrend
                    .map((point, pointIdx) => {
                      const x =
                        dailyTrend.length > 1 ? (pointIdx / (dailyTrend.length - 1)) * 400 : 200
                      return `${x},${point.y}`
                    })
                    .join(' ')
                "
                fill="none"
                stroke="#1E6FD9"
                stroke-width="3"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
              <circle
                v-for="(point, pointIdx) in dailyTrend"
                :key="point.dayLabel"
                :cx="dailyTrend.length > 1 ? (pointIdx / (dailyTrend.length - 1)) * 400 : 200"
                :cy="point.y"
                r="5"
                fill="#1E6FD9"
                stroke="#fff"
                stroke-width="2"
              />
            </svg>
            <div class="trend-x-labels">
              <span v-for="point in dailyTrend" :key="point.dayLabel" class="trend-x-item">
                <em class="trend-x-value" :class="point.change < 0 ? 'num-sub' : 'num-add'">
                  {{ point.change > 0 ? '+' : '' }}{{ point.change }}
                </em>
                {{ point.dayLabel }}
              </span>
            </div>
          </div>
        </div>
      </el-col>
    </el-row>
  </div>
</template>

<style scoped>
.page {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.welcome-card {
  background: linear-gradient(135deg, #1e3a8a 0%, #2b5ce6 100%);
  border: none;
  color: #fff;
}

.welcome-card :deep(.el-card__body) {
  padding: 24px 32px;
}

.welcome-inner {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.welcome-greeting {
  font-size: 22px;
  font-weight: 600;
}

.welcome-sub {
  margin-top: 8px;
  font-size: 14px;
  opacity: 0.9;
}

.stat-row {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 16px;
}

.stat-item {
  background: #fff;
  padding: 20px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  gap: 16px;
  box-shadow: 0 1px 4px rgba(0, 21, 41, 0.05);
}

.stat-icon {
  width: 48px;
  height: 48px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.stat-num {
  font-size: 24px;
  font-weight: 700;
  color: #303133;
  font-variant-numeric: tabular-nums;
}

.stat-label {
  font-size: 13px;
  color: #909399;
  margin-top: 2px;
}

.num-add {
  color: #52c41a;
}

.num-sub {
  color: #f56c6c;
}

.dashboard-card {
  background: #fff;
  border-radius: 8px;
  padding: 18px 20px 20px;
  box-shadow: 0 1px 4px rgba(0, 21, 41, 0.05);
  min-height: 260px;
}

.dashboard-card-title {
  font-size: 15px;
  font-weight: 600;
  color: #303133;
  margin-bottom: 16px;
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 8px;
}

.card-sub {
  font-size: 12px;
  font-weight: 400;
  color: #909399;
}

.empty-mini {
  text-align: center;
  padding: 60px 20px;
  color: #9ca3af;
  font-size: 14px;
}

/* 班级积分对比柱状图 */
.bar-chart {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.bar-item {
  display: flex;
  align-items: center;
  gap: 12px;
}

.bar-label {
  width: 110px;
  flex-shrink: 0;
  font-size: 13px;
  color: #1f2937;
  font-weight: 500;
  text-align: right;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.bar-track {
  flex: 1;
  height: 26px;
  background: #f0f4fa;
  border-radius: 6px;
  overflow: hidden;
}

.bar-fill {
  height: 100%;
  background: linear-gradient(90deg, #1e6fd9, #4d7bed);
  border-radius: 6px;
  transition: width 0.4s ease;
  display: flex;
  align-items: center;
  padding-left: 10px;
  min-width: 44px;
  box-sizing: border-box;
}

.bar-value {
  font-size: 13px;
  font-weight: 700;
  color: #fff;
  font-variant-numeric: tabular-nums;
}

/* 近 7 天积分变动折线图 */
.trend-chart {
  position: relative;
  height: 190px;
  padding-top: 10px;
}

.trend-grid {
  position: absolute;
  top: 10px;
  left: 0;
  right: 0;
  bottom: 46px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

.grid-line {
  height: 1px;
  background: #eef1f6;
}

.trend-line {
  position: absolute;
  top: 10px;
  left: 0;
  right: 0;
  bottom: 46px;
  width: 100%;
  height: calc(100% - 56px);
  overflow: visible;
}

.trend-x-labels {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  display: flex;
  justify-content: space-between;
}

.trend-x-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
  font-size: 12px;
  color: #6b7280;
}

.trend-x-value {
  font-size: 12px;
  font-weight: 600;
  font-style: normal;
  font-variant-numeric: tabular-nums;
}
</style>