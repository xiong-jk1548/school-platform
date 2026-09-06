<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Edit, Delete, Search, Download } from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'
import { exportToExcel } from '@/utils/excel'

const userStore = useUserStore()

interface ClassOpt {
  id: string
  name: string
}

interface StudentRow {
  id: string
  name: string
  student_name?: string
  student_no?: string
  class_id: string
  class_name?: string
  total_score?: number
}

const keyword = ref('')
const filterClassId = ref('')
const loading = ref(false)
const students = ref<StudentRow[]>([])
const classes = ref<ClassOpt[]>([])

// 学生编辑弹窗
const editDialogVisible = ref(false)
const editIsEdit = ref(false)
const editFormRef = ref()
const editForm = ref<StudentRow>({
  id: '',
  name: '',
  student_name: '',
  student_no: '',
  class_id: '',
})

async function loadClasses() {
  if (!userStore.schoolId) return
  try {
    const { data, error } = await supabase
      .from('classes')
      .select('id, name, class_name')
      .eq('school_id', userStore.schoolId)
      .order('name', { ascending: true })
    if (error) throw error
    const rows = (data ?? []) as ClassOpt[]
    rows.forEach((c: any) => { if (!c.name && c.class_name) c.name = c.class_name })
    classes.value = rows
  } catch (err: any) {
    ElMessage.error(err.message || '加载班级下拉失败')
  }
}

function getClassName(classId: string) {
  return classes.value.find((c) => c.id === classId)?.name ?? '-'
}

async function loadStudents() {
  if (!userStore.schoolId) return
  loading.value = true
  try {
    let query = supabase
      .from('students')
      .select('*')
      .eq('school_id', userStore.schoolId)
    if (filterClassId.value) {
      query = query.eq('class_id', filterClassId.value)
    }
    if (keyword.value.trim()) {
      const kw = `%${keyword.value.trim()}%`
      query = query.or(`student_name.ilike.${kw},name.ilike.${kw},student_no.ilike.${kw}`)
    }
    const { data, error } = await query.order('student_name', { ascending: true })
    if (error) throw error

    const rows = (data ?? []) as StudentRow[]
    rows.forEach((s: any) => {
      if (!s.student_name && s.name) s.student_name = s.name
      if (!s.name && s.student_name) s.name = s.student_name
    })
    for (const s of rows) {
      s.class_name = getClassName(s.class_id)
    }
    students.value = rows
  } catch (err: any) {
    ElMessage.error(err.message || '加载学生列表失败')
  } finally {
    loading.value = false
  }
}

const exportRows = computed(() =>
  students.value.map((s) => ({
    姓名: s.student_name || s.name,
    学号: s.student_no ?? '',
    班级: s.class_name ?? '',
    总积分: s.total_score ?? 0,
  })),
)

function handleExport() {
  if (exportRows.value.length === 0) {
    ElMessage.warning('暂无可导出的数据')
    return
  }
  exportToExcel(exportRows.value, `学生列表_${Date.now()}.xlsx`)
}

// ===== 学生 CRUD =====
function openAddStudent() {
  editIsEdit.value = false
  editForm.value = {
    id: '',
    name: '',
    student_name: '',
    student_no: '',
    class_id: filterClassId.value || classes.value[0]?.id || '',
  }
  editDialogVisible.value = true
}

function openEditStudent(row: StudentRow) {
  editIsEdit.value = true
  editForm.value = { ...row, student_name: row.student_name || row.name, name: row.student_name || row.name }
  editDialogVisible.value = true
}

async function handleSubmitStudent() {
  try {
    await editFormRef.value?.validate()
  } catch {
    return
  }
  const student_name = editForm.value.student_name?.trim() || editForm.value.name?.trim()
  if (!student_name) {
    ElMessage.warning('请输入学生姓名')
    return
  }
  if (!editForm.value.class_id) {
    ElMessage.warning('请选择所属班级')
    return
  }
  try {
    if (editIsEdit.value) {
      const { error } = await supabase
        .from('students')
        .update({
          student_name,
          name: student_name,
          student_no: editForm.value.student_no?.trim() || null,
          class_id: editForm.value.class_id,
        })
        .eq('id', editForm.value.id)
      if (error) throw error
      ElMessage.success('更新成功')
    } else {
      const { error } = await supabase.from('students').insert({
        student_name,
        name: student_name,
        student_no: editForm.value.student_no?.trim() || null,
        class_id: editForm.value.class_id,
        school_id: userStore.schoolId || null,
        total_score: 0,
      })
      if (error) throw error
      ElMessage.success('新增成功')
    }
    editDialogVisible.value = false
    await loadStudents()
  } catch (err: any) {
    ElMessage.error(err.message || '保存失败')
  }
}

async function handleDeleteStudent(row: StudentRow) {
  try {
    await ElMessageBox.confirm(
      `确定删除学生「${row.student_name || row.name}」吗？`,
      '提示',
      { type: 'warning' },
    )
  } catch {
    return
  }
  try {
    const { error } = await supabase.from('students').delete().eq('id', row.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadStudents()
  } catch (err: any) {
    ElMessage.error(err.message || '删除失败')
  }
}

onMounted(async () => {
  await loadClasses()
  await loadStudents()
})
</script>

<template>
  <el-card>
    <template #header>
      <div class="card-header">
        <span>本校学生列表</span>
        <el-button type="primary" :icon="Plus" @click="openAddStudent">新增学生</el-button>
      </div>
    </template>

    <el-form inline style="margin-bottom: 16px">
      <el-form-item label="关键词">
        <el-input
          v-model="keyword"
          placeholder="姓名 / 学号"
          clearable
          style="width: 220px"
        />
      </el-form-item>
      <el-form-item label="班级">
        <el-select v-model="filterClassId" placeholder="全部班级" clearable style="width: 180px">
          <el-option v-for="c in classes" :key="c.id" :label="c.name" :value="c.id" />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" :icon="Search" @click="loadStudents">搜索</el-button>
        <el-button :icon="Download" @click="handleExport">导出 Excel</el-button>
      </el-form-item>
    </el-form>

    <el-table :data="students" v-loading="loading" stripe style="width: 100%">
      <el-table-column prop="student_name" label="姓名" min-width="120">
        <template #default="{ row }">{{ row.student_name || row.name }}</template>
      </el-table-column>
      <el-table-column prop="student_no" label="学号" min-width="140">
        <template #default="{ row }">{{ row.student_no || '-' }}</template>
      </el-table-column>
      <el-table-column prop="class_name" label="班级" min-width="160" />
      <el-table-column label="总积分" min-width="120">
        <template #default="{ row }">
          <el-tag :type="(row.total_score ?? 0) >= 0 ? 'success' : 'danger'">
            {{ row.total_score ?? 0 }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="180" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" :icon="Edit" @click="openEditStudent(row as StudentRow)">编辑</el-button>
          <el-button link type="danger" :icon="Delete" @click="handleDeleteStudent(row as StudentRow)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <!-- 学生 新增/编辑 弹窗 -->
    <el-dialog
      v-model="editDialogVisible"
      :title="editIsEdit ? '编辑学生' : '新增学生'"
      width="460px"
      destroy-on-close
    >
      <el-form ref="editFormRef" :model="editForm" label-width="80px">
        <el-form-item
          label="姓名"
          prop="student_name"
          :rules="[{ required: true, message: '请输入姓名', trigger: 'blur' }]"
        >
          <el-input v-model="editForm.student_name" placeholder="请输入学生姓名" maxlength="20" />
        </el-form-item>
        <el-form-item label="学号" prop="student_no">
          <el-input v-model="editForm.student_no" placeholder="选填" maxlength="30" />
        </el-form-item>
        <el-form-item
          label="班级"
          prop="class_id"
          :rules="[{ required: true, message: '请选择班级', trigger: 'change' }]"
        >
          <el-select v-model="editForm.class_id" placeholder="请选择班级" style="width: 100%">
            <el-option v-for="c in classes" :key="c.id" :label="c.name" :value="c.id" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="editDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="handleSubmitStudent">确定</el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<style scoped>
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
</style>
