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
  class_id?: string
  score?: number
  remark?: string
  operate_user_id?: string
  operate_user_name?: string
  created_at?: string
}

const dateRange = ref<[string, string] | null>(null)
const loading = ref(false)
const logs = ref<LogRow[]>([])

const filterClassId = ref<string>('')
const schoolClasses = ref<{ id: string; class_name: string }[]>([])

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

async function loadLogs() {
  if (!userStore.schoolId) return
  loading.value = true
  try {
    let query = supabase
      .from('score_log')
      .select('*')
      .eq('school_id', userStore.schoolId)
      .order('created_at', { ascending: false })
    if (dateRange.value && dateRange.value.length === 2) {
      const [start, end] = dateRange.value
      query = query.gte('created_at', start).lte('created_at', end)
    }
    const { data, error } = await query.limit(500)
    if (error) throw error
    const rows = (data ?? []) as LogRow[]

    const studentIds = Array.from(new Set(rows.map((r) => r.student_id).filter(Boolean)))
    const operatorIds = Array.from(
      new Set(rows.map((r) => r.operate_user_id).filter(Boolean) as string[]),
    )

    const [stuRes, opRes] = await Promise.all([
      studentIds.length > 0
        ? supabase.from('students').select('id, name, class_id').in('id', studentIds)
        : Promise.resolve({ data: [], error: null }),
      operatorIds.length > 0
        ? supabase.from('profiles').select('id, real_name').in('id', operatorIds)
        : Promise.resolve({ data: [], error: null }),
    ])

    let classesMap: Record<string, string> = {}
    if (studentIds.length > 0) {
      const classIds = Array.from(
        new Set(((stuRes.data as any[]) ?? []).map((s) => s.class_id).filter(Boolean)),
      )
      if (classIds.length > 0) {
        const { data: classRes } = await supabase
          .from('classes')
          .select('id, name')
          .in('id', classIds)
        classesMap = Object.fromEntries(((classRes as any[]) ?? []).map((c) => [c.id, c.name]))
      }
    }

    const stuMap = Object.fromEntries(
      (((stuRes as any).data as any[]) ?? []).map((s: any) => [s.id, s]),
    )
    const opMap = Object.fromEntries(
      (((opRes as any).data as any[]) ?? []).map((p: any) => [p.id, p]),
    )

    for (const r of rows) {
      const stu = stuMap[r.student_id]
      r.student_name = stu?.name ?? '-'
      r.class_id = stu?.class_id
      r.class_name = stu?.class_id ? classesMap[stu.class_id] ?? '-' : '-'
      r.operate_user_name = r.operate_user_id ? opMap[r.operate_user_id]?.real_name ?? '-' : '-'
    }
    logs.value = rows
  } catch (err: any) {
    ElMessage.error(err.message || '加载积分流水失败')
  } finally {
    loading.value = false
  }
}

const exportRows = computed(() =>
  filteredLogs.value.map((r) => ({
    学生: r.student_name ?? '',
    班级: r.class_name ?? '',
    变动值: r.score ?? 0,
    备注: r.remark ?? '',
    操作人: r.operate_user_name ?? '',
    时间: r.created_at ?? '',
  })),
)

const filteredLogs = computed(() => {
  let list = logs.value
  if (userStore.role === 'school_admin' && filterClassId.value) {
    list = list.filter((r) => r.class_id === filterClassId.value)
  }
  return list
})

function handleExport() {
  if (exportRows.value.length === 0) {
    ElMessage.warning('暂无可导出的数据')
    return
  }
  exportToExcel(exportRows.value, `积分流水_${Date.now()}.xlsx`)
}

onMounted(async () => {
  await loadSchoolClasses()
  await loadLogs()
})
</script>

<template>
  <el-card>
    <template #header>
      <div class="card-header">
        <span>本校积分流水</span>
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
      <el-form-item v-if="userStore.role === 'school_admin'" label="班级">
        <el-select
          v-model="filterClassId"
          clearable
          placeholder="全部班级"
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
      </el-form-item>
      <el-form-item>
        <el-button type="primary" :icon="Search" @click="loadLogs">筛选</el-button>
        <el-button :icon="Download" @click="handleExport">导出 Excel</el-button>
      </el-form-item>
    </el-form>

    <el-table :data="filteredLogs" v-loading="loading" stripe style="width: 100%">
      <el-table-column prop="student_name" label="学生" min-width="120" />
      <el-table-column prop="class_name" label="班级" min-width="140" />
      <el-table-column label="变动值" min-width="100">
        <template #default="{ row }">
          <el-tag :type="(row.score ?? 0) >= 0 ? 'success' : 'danger'">
            {{ row.score && row.score > 0 ? '+' : '' }}{{ row.score ?? 0 }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="remark" label="备注" min-width="180">
        <template #default="{ row }">{{ row.remark || '-' }}</template>
      </el-table-column>
      <el-table-column prop="operate_user_name" label="操作人" min-width="120" />
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
