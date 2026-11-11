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

/**
 * 加载本校班级列表，用于「班级」筛选下拉。
 * 仅学校管理员需要该筛选，其他角色直接跳过以省掉一次请求。
 * @returns 无返回值，结果写入响应式变量 schoolClasses
 */
async function loadSchoolClasses() {
  if (userStore.role !== 'school_admin' || !userStore.schoolId) return
  try {
    const { data: classData, error } = await supabase
      .from('classes')
      .select('id, class_name')
      .eq('school_id', userStore.schoolId)
    if (error) throw error
    schoolClasses.value = (classData ?? []) as { id: string; class_name: string }[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载班级列表失败')
  }
}

/**
 * 查询本校积分流水（最多 500 条），并把学生姓名、班级名、操作人姓名补全到每行记录上。
 * 时间范围筛选按 created_at 生效；学生与操作人信息通过 id 批量反查后在前端拼装。
 * @returns 无返回值，结果写入响应式变量 logs
 */
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
    const { data: logData, error } = await query.limit(500)
    if (error) throw error
    const logRows = (logData ?? []) as LogRow[]

    const studentIds = Array.from(new Set(logRows.map((log) => log.student_id).filter(Boolean)))
    const operatorIds = Array.from(
      new Set(logRows.map((log) => log.operate_user_id).filter(Boolean) as string[]),
    )

    const [studentRes, operatorRes] = await Promise.all([
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
        new Set(((studentRes.data as any[]) ?? []).map((student) => student.class_id).filter(Boolean)),
      )
      if (classIds.length > 0) {
        const { data: classRows } = await supabase
          .from('classes')
          .select('id, name')
          .in('id', classIds)
        classesMap = Object.fromEntries(((classRows as any[]) ?? []).map((cls) => [cls.id, cls.name]))
      }
    }

    const studentMap = Object.fromEntries(
      (((studentRes as any).data as any[]) ?? []).map((student: any) => [student.id, student]),
    )
    const operatorMap = Object.fromEntries(
      (((operatorRes as any).data as any[]) ?? []).map((profile: any) => [profile.id, profile]),
    )

    for (const log of logRows) {
      const student = studentMap[log.student_id]
      log.student_name = student?.name ?? '-'
      log.class_id = student?.class_id
      log.class_name = student?.class_id ? classesMap[student.class_id] ?? '-' : '-'
      log.operate_user_name = log.operate_user_id ? operatorMap[log.operate_user_id]?.real_name ?? '-' : '-'
    }
    logs.value = logRows
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载积分流水失败')
  } finally {
    loading.value = false
  }
}

/** 表格导出用的行数据：把积分流水映射为中文表头的二维数据 */
const exportRows = computed(() =>
  filteredLogs.value.map((log) => ({
    学生: log.student_name ?? '',
    班级: log.class_name ?? '',
    变动值: log.score ?? 0,
    备注: log.remark ?? '',
    操作人: log.operate_user_name ?? '',
    时间: log.created_at ?? '',
  })),
)

/**
 * 按「班级」下拉筛选流水列表；非学校管理员不做班级过滤。
 * @returns 过滤后的积分流水数组
 */
const filteredLogs = computed(() => {
  let resultLogs = logs.value
  if (userStore.role === 'school_admin' && filterClassId.value) {
    resultLogs = resultLogs.filter((log) => log.class_id === filterClassId.value)
  }
  return resultLogs
})

/**
 * 导出当前筛选结果为 Excel；无数据时给出提示。
 * @returns 无返回值，触发浏览器下载
 */
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
            v-for="classItem in schoolClasses"
            :key="classItem.id"
            :label="classItem.class_name"
            :value="classItem.id"
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
