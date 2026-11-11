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

/**
 * 加载当前登录教师本人的积分操作流水（最多 500 条，可按时间范围过滤）
 * 流水表只存了 student_id，这里再批量查学生与班级，回填 student_name / class_name
 * @returns 无返回值（副作用：写入 logs，并在 finally 中复位 loading）
 */
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
    const { data: logRows, error } = await query.limit(500)
    if (error) throw error
    const logList = (logRows ?? []) as LogRow[]

    const studentIds = Array.from(new Set(logList.map((log) => log.student_id).filter(Boolean)))
    if (studentIds.length > 0) {
      const { data: studentRows, error: studentError } = await supabase
        .from('students')
        .select('id, name, class_id')
        .in('id', studentIds)
      if (studentError) throw studentError

      const classIds = Array.from(
        new Set(((studentRows ?? []) as any[]).map((student) => student.class_id).filter(Boolean)),
      )
      let classNamesById: Record<string, string> = {}
      if (classIds.length > 0) {
        const { data: classRows } = await supabase.from('classes').select('id, name').in('id', classIds)
        classNamesById = Object.fromEntries(((classRows ?? []) as any[]).map((classRow) => [classRow.id, classRow.name]))
      }

      const studentsById = Object.fromEntries(
        ((studentRows ?? []) as any[]).map((student: any) => [student.id, student]),
      )
      for (const log of logList) {
        const student = studentsById[log.student_id]
        log.student_name = student?.name ?? '-'
        log.class_name = student?.class_id ? classNamesById[student.class_id] ?? '-' : '-'
      }
    }
    logs.value = logList
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载操作流水失败')
  } finally {
    loading.value = false
  }
}

// 把流水记录转换成导出用的中文表头行数据
const exportRows = computed(() =>
  logs.value.map((log) => ({
    学生: log.student_name ?? '',
    班级: log.class_name ?? '',
    变动值: log.score ?? 0,
    备注: log.remark ?? '',
    时间: log.created_at ?? '',
  })),
)

/**
 * 导出当前筛选结果中的操作流水为 Excel
 * @returns 无返回值（副作用：下载 xlsx 文件；无数据时仅提示不导出）
 */
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
        <template #default="{ row: logRow }">
          <el-tag :type="(logRow.score ?? 0) >= 0 ? 'success' : 'danger'">
            {{ logRow.score && logRow.score > 0 ? '+' : '' }}{{ logRow.score ?? 0 }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="remark" label="备注" min-width="200">
        <template #default="{ row: logRow }">{{ logRow.remark || '-' }}</template>
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
