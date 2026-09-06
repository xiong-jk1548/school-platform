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

async function loadData() {
  loading.value = true
  try {
    const [
      { count: schoolCount, error: schErr },
      { count: studentCount, error: stuErr },
    ] = await Promise.all([
      supabase.from('schools').select('*', { count: 'exact', head: true }),
      supabase.from('students').select('*', { count: 'exact', head: true }),
    ])
    if (schErr) throw schErr
    if (stuErr) throw stuErr

    const now = new Date()
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString()

    const { data: logs, error: logErr } = await supabase
      .from('score_log')
      .select('score, created_at, students!inner(school_id)')
      .gte('created_at', monthStart)
    if (logErr) throw logErr

    const monthTotal = (logs ?? []).reduce(
      (acc: number, l: any) => acc + (Number(l.score) || 0),
      0,
    )

    summary.value = {
      schoolCount: schoolCount ?? 0,
      studentCount: studentCount ?? 0,
      monthTotal,
    }

    await loadSchoolStats(monthStart)
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '加载统计数据失败')
  } finally {
    loading.value = false
  }
}

async function loadSchoolStats(monthStart: string) {
  const { data: schools, error: schErr } = await supabase
    .from('schools')
    .select('id, name')
    .order('name')
  if (schErr) throw schErr

  const { data: students, error: stuErr } = await supabase
    .from('students')
    .select('id, school_id, total_score')
  if (stuErr) throw stuErr

  const { data: logs, error: logErr } = await supabase
    .from('score_log')
    .select('score, created_at, students!inner(school_id)')
  if (logErr) throw logErr

  const result: SchoolStatRow[] = []

  for (const s of schools ?? []) {
    const sid = s.id
    const schoolStudents = (students ?? []).filter(
      (st: any) => st.school_id === sid,
    )
    const studentCount = schoolStudents.length
    const totalScore = schoolStudents.reduce(
      (acc: number, st: any) => acc + (Number(st.total_score) || 0),
      0,
    )

    const monthLogs = (logs ?? []).filter(
      (l: any) =>
        l.students?.school_id === sid &&
        l.created_at >= monthStart,
    )
    const monthAdd = monthLogs
      .filter((l: any) => Number(l.score) > 0)
      .reduce((acc: number, l: any) => acc + Number(l.score), 0)
    const monthSub = monthLogs
      .filter((l: any) => Number(l.score) < 0)
      .reduce((acc: number, l: any) => acc + Math.abs(Number(l.score)), 0)

    result.push({
      school_id: sid,
      school_name: s.name,
      student_count: studentCount,
      total_score: totalScore,
      month_change: monthAdd - monthSub,
      month_add: monthAdd,
      month_sub: monthSub,
    })
  }

  tableData.value = result
}

function handleExport() {
  const exportRows = tableData.value.map((row) => ({
    学校名称: row.school_name,
    学生数: row.student_count,
    总积分: row.total_score,
    本月加分: row.month_add,
    本月减分: row.month_sub,
    本月净变动: row.month_change,
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
        v-for="(card, idx) in statCards"
        :key="card.title"
        class="stat-card"
        :style="{ borderTopColor: card.color }"
      >
        <div class="stat-info">
          <div class="stat-title">{{ card.title }}</div>
          <div class="stat-value">
            {{
              idx === 0
                ? summary.schoolCount
                : idx === 1
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
          <template #default="{ row }">
            <span class="score-total">{{ row.total_score }}</span>
          </template>
        </el-table-column>
        <el-table-column label="本月加分" width="120" align="right">
          <template #default="{ row }">
            <span class="score-add">+{{ row.month_add }}</span>
          </template>
        </el-table-column>
        <el-table-column label="本月减分" width="120" align="right">
          <template #default="{ row }">
            <span class="score-sub">-{{ row.month_sub }}</span>
          </template>
        </el-table-column>
        <el-table-column label="本月净变动" width="130" align="right">
          <template #default="{ row }">
            <span
              :class="
                row.month_change > 0
                  ? 'score-add'
                  : row.month_change < 0
                    ? 'score-sub'
                    : ''
              "
            >
              {{ row.month_change > 0 ? '+' : '' }}{{ row.month_change }}
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
