<script setup lang="ts">
import { ElMessage } from 'element-plus'
import { ref, onMounted } from 'vue'
import { supabase } from '@/api/supabase'
import { exportToExcel } from '@/utils/excel'
import { School, User, TrendCharts, Download } from '@element-plus/icons-vue'

interface StatCard {
  title: string
  value: string | number
  icon: any
  color: string
}

interface SchoolStatRow {
  school_id: string
  school_name: string
  student_count: number
  total_score: number
  month_change: number
  month_add: number
  month_sub: number
}

const loading = ref(false)
const summary = ref({
  schoolCount: 0,
  studentCount: 0,
  monthTotal: 0,
})
const tableData = ref<SchoolStatRow[]>([])

const statCards: StatCard[] = [
  { title: '学校总数', value: 0, icon: School, color: '#1E6FD9' },
  { title: '学生总数', value: 0, icon: User, color: '#52c41a' },
  { title: '本月积分变动', value: 0, icon: TrendCharts, color: '#fa8c16' },
]

/**
 * 加载统计报表顶部的三张汇总卡片（学校总数、学生总数、本月积分变动），
 * 随后继续加载各学校明细。
 * @returns 无返回值，汇总写入 summary，明细写入 tableData
 */
async function loadData() {
  loading.value = true
  try {
    const [
      { count: schoolTotal, error: schoolQueryError },
      { count: studentTotal, error: studentQueryError },
    ] = await Promise.all([
      supabase.from('schools').select('*', { count: 'exact', head: true }),
      supabase.from('students').select('*', { count: 'exact', head: true }),
    ])
    if (schoolQueryError) throw schoolQueryError
    if (studentQueryError) throw studentQueryError

    const now = new Date()
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString()

    const { data: scoreLogs, error: logQueryError } = await supabase
      .from('score_log')
      .select('score, created_at, students!inner(school_id)')
      .gte('created_at', monthStart)
    if (logQueryError) throw logQueryError

    const monthTotal = (scoreLogs ?? []).reduce(
      (acc: number, scoreLog: any) => acc + (Number(scoreLog.score) || 0),
      0,
    )

    summary.value = {
      schoolCount: schoolTotal ?? 0,
      studentCount: studentTotal ?? 0,
      monthTotal,
    }

    await loadSchoolStats(monthStart)
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '加载统计数据失败')
  } finally {
    loading.value = false
  }
}

/**
 * 按学校维度汇总积分明细：学生数、总积分，以及本月加分、减分与净变动。
 * @param monthStart 本月起始时间（ISO 字符串），用于筛出本月积分流水
 * @returns 无返回值，汇总结果写入 tableData
 */
async function loadSchoolStats(monthStart: string) {
  const { data: schoolList, error: schoolQueryError } = await supabase
    .from('schools')
    .select('id, name')
    .order('name')
  if (schoolQueryError) throw schoolQueryError

  const { data: studentList, error: studentQueryError } = await supabase
    .from('students')
    .select('id, school_id, total_score')
  if (studentQueryError) throw studentQueryError

  const { data: scoreLogs, error: logQueryError } = await supabase
    .from('score_log')
    .select('score, created_at, students!inner(school_id)')
  if (logQueryError) throw logQueryError

  const schoolStatList: SchoolStatRow[] = []

  for (const school of schoolList ?? []) {
    const schoolId = school.id
    const schoolStudents = (studentList ?? []).filter(
      (student: any) => student.school_id === schoolId,
    )
    const studentCount = schoolStudents.length
    const totalScore = schoolStudents.reduce(
      (acc: number, student: any) => acc + (Number(student.total_score) || 0),
      0,
    )

    const monthLogs = (scoreLogs ?? []).filter(
      (scoreLog: any) =>
        scoreLog.students?.school_id === schoolId &&
        scoreLog.created_at >= monthStart,
    )
    const monthAdd = monthLogs
      .filter((scoreLog: any) => Number(scoreLog.score) > 0)
      .reduce((acc: number, scoreLog: any) => acc + Number(scoreLog.score), 0)
    const monthSub = monthLogs
      .filter((scoreLog: any) => Number(scoreLog.score) < 0)
      .reduce((acc: number, scoreLog: any) => acc + Math.abs(Number(scoreLog.score)), 0)

    schoolStatList.push({
      school_id: schoolId,
      school_name: school.name,
      student_count: studentCount,
      total_score: totalScore,
      month_change: monthAdd - monthSub,
      month_add: monthAdd,
      month_sub: monthSub,
    })
  }

  tableData.value = schoolStatList
}

/**
 * 把各学校统计明细整理成中文表头后导出为 Excel 文件。
 * @returns 无返回值，导出成功后在页面给出提示
 */
function handleExport() {
  const exportRows = tableData.value.map((schoolStat) => ({
    学校名称: schoolStat.school_name,
    学生数: schoolStat.student_count,
    总积分: schoolStat.total_score,
    本月加分: schoolStat.month_add,
    本月减分: schoolStat.month_sub,
    本月净变动: schoolStat.month_change,
  }))
  exportToExcel(exportRows, '全区积分统计')
  ElMessage.success('导出成功')
}

onMounted(loadData)
</script>

<template>
  <div class="page">
    <div class="stat-cards">
      <div
        v-for="(card, cardIndex) in statCards"
        :key="card.title"
        class="stat-card"
        :style="{ borderTopColor: card.color }"
      >
        <div class="stat-info">
          <div class="stat-title">{{ card.title }}</div>
          <div class="stat-value">
            {{
              cardIndex === 0
                ? summary.schoolCount
                : cardIndex === 1
                  ? summary.studentCount
                  : summary.monthTotal
            }}
          </div>
        </div>
        <div class="stat-icon" :style="{ background: card.color + '1a', color: card.color }">
          <el-icon :size="28"><component :is="card.icon" /></el-icon>
        </div>
      </div>
    </div>

    <el-card shadow="never">
      <template #header>
        <div class="card-header">
          <span>各学校积分统计</span>
          <el-button
            type="primary"
            :icon="Download"
            :loading="loading"
            @click="handleExport"
          >
            导出 Excel
          </el-button>
        </div>
      </template>

      <el-table :data="tableData" v-loading="loading" stripe>
        <el-table-column prop="school_name" label="学校名称" min-width="180" />
        <el-table-column prop="student_count" label="学生数" width="100" align="center" />
        <el-table-column prop="total_score" label="总积分" width="120" align="right">
          <template #default="{ row: schoolStat }">
            <span class="score-total">{{ schoolStat.total_score }}</span>
          </template>
        </el-table-column>
        <el-table-column label="本月加分" width="120" align="right">
          <template #default="{ row: schoolStat }">
            <span class="score-add">+{{ schoolStat.month_add }}</span>
          </template>
        </el-table-column>
        <el-table-column label="本月减分" width="120" align="right">
          <template #default="{ row: schoolStat }">
            <span class="score-sub">-{{ schoolStat.month_sub }}</span>
          </template>
        </el-table-column>
        <el-table-column label="本月净变动" width="130" align="right">
          <template #default="{ row: schoolStat }">
            <span
              :class="
                schoolStat.month_change > 0
                  ? 'score-add'
                  : schoolStat.month_change < 0
                    ? 'score-sub'
                    : ''
              "
            >
              {{ schoolStat.month_change > 0 ? '+' : '' }}{{ schoolStat.month_change }}
            </span>
          </template>
        </el-table-column>
      </el-table>

      <div class="footer-hint">共 {{ tableData.length }} 所学校</div>
    </el-card>
  </div>
</template>

<style scoped>
.page {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.stat-cards {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
}

.stat-card {
  background: #fff;
  padding: 20px 24px;
  border-radius: 8px;
  border-top: 3px solid;
  display: flex;
  justify-content: space-between;
  align-items: center;
  box-shadow: 0 1px 4px rgba(0, 21, 41, 0.05);
}

.stat-title {
  font-size: 14px;
  color: #909399;
  margin-bottom: 8px;
}

.stat-value {
  font-size: 28px;
  font-weight: 700;
  color: #303133;
}

.stat-icon {
  width: 56px;
  height: 56px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.score-total {
  font-weight: 600;
  color: #303133;
}

.score-add {
  color: #52c41a;
  font-weight: 600;
}

.score-sub {
  color: #f56c6c;
  font-weight: 600;
}

.footer-hint {
  margin-top: 12px;
  font-size: 12px;
  color: #909399;
}
</style>
