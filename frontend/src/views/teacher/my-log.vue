<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { ElMessage } from 'element-plus'
import { Search, Download } from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'
import { exportToExcel } from '@/utils/excel'

const userStore = useUserStore()

interface LogRow {
  id: string
  student_id: string
  student_name?: string
  class_name?: string
  score?: number
  remark?: string
  created_at?: string
}

const loading = ref(false)
const logs = ref<LogRow[]>([])
const dateRange = ref<[string, string] | null>(null)

async function loadLogs() {
  if (!userStore.id) return
  loading.value = true
  try {
    let query = supabase
      .from('score_log')
      .select('*')
      .eq('operate_user_id', userStore.id)
      .order('created_at', { ascending: false })
    if (dateRange.value && dateRange.value.length === 2) {
      const [start, end] = dateRange.value
      query = query.gte('created_at', start).lte('created_at', end)
    }
    const { data, error } = await query.limit(500)
    if (error) throw error
    const rows = (data ?? []) as LogRow[]

    const studentIds = Array.from(new Set(rows.map((r) => r.student_id).filter(Boolean)))
    if (studentIds.length > 0) {
      const { data: stuRes, error: stuErr } = await supabase
        .from('students')
        .select('id, name, class_id')
        .in('id', studentIds)
      if (stuErr) throw stuErr

      const classIds = Array.from(
        new Set(((stuRes ?? []) as any[]).map((s) => s.class_id).filter(Boolean)),
      )
      let classesMap: Record<string, string> = {}
      if (classIds.length > 0) {
        const { data: classRes } = await supabase.from('classes').select('id, name').in('id', classIds)
        classesMap = Object.fromEntries(((classRes ?? []) as any[]).map((c) => [c.id, c.name]))
      }

      const stuMap = Object.fromEntries(
        ((stuRes ?? []) as any[]).map((s: any) => [s.id, s]),
      )
      for (const r of rows) {
        const stu = stuMap[r.student_id]
        r.student_name = stu?.name ?? '-'
        r.class_name = stu?.class_id ? classesMap[stu.class_id] ?? '-' : '-'
      }
    }
    logs.value = rows
  } catch (err: any) {
    ElMessage.error(err.message || '加载操作流水失败')
  } finally {
    loading.value = false
  }
}

const exportRows = computed(() =>
  logs.value.map((r) => ({
    学生: r.student_name ?? '',
    班级: r.class_name ?? '',
    变动值: r.score ?? 0,
    备注: r.remark ?? '',
    时间: r.created_at ?? '',
  })),
)

function handleExport() {
  if (exportRows.value.length === 0) {
    ElMessage.warning('暂无可导出的数据')
    return
  }
  exportToExcel(exportRows.value, `我的积分流水_${Date.now()}.xlsx`)
}

onMounted(loadLogs)
</script>

<template>
  <el-card>
    <template #header>
      <div class="card-header">
        <span>本人操作流水</span>
      </div>
    </template>

    <el-form inline style="margin-bottom: 16px">
      <el-form-item label="时间范围">
        <el-date-picker
          v-model="dateRange"
          type="datetimerange"
          range-separator="至"
          start-placeholder="开始时间"
          end-placeholder="结束时间"
          value-format="YYYY-MM-DDTHH:mm:ss"
          style="width: 420px"
        />
      </el-form-item>
      <el-form-item>
        <el-button type="primary" :icon="Search" @click="loadLogs">筛选</el-button>
        <el-button :icon="Download" @click="handleExport">导出 Excel</el-button>
      </el-form-item>
    </el-form>

    <el-table :data="logs" v-loading="loading" stripe style="width: 100%">
      <el-table-column prop="student_name" label="学生" min-width="120" />
      <el-table-column prop="class_name" label="班级" min-width="140" />
      <el-table-column label="变动值" min-width="100">
        <template #default="{ row }">
          <el-tag :type="(row.score ?? 0) >= 0 ? 'success' : 'danger'">
            {{ row.score && row.score > 0 ? '+' : '' }}{{ row.score ?? 0 }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="remark" label="备注" min-width="200">
        <template #default="{ row }">{{ row.remark || '-' }}</template>
      </el-table-column>
      <el-table-column prop="created_at" label="时间" min-width="180" />
    </el-table>
  </el-card>
</template>

<style scoped>
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
</style>
