<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Edit, Delete, Upload, Download } from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'
import { exportToExcel } from '@/utils/excel'
import * as XLSX from 'xlsx'
import ScoreDialog from './ScoreDialog.vue'

const userStore = useUserStore()

interface StudentRow {
  id: string
  student_name: string
  name?: string
  student_no?: string
  total_score?: number
  class_id?: string
  class_name?: string
}

const students = ref<StudentRow[]>([])
const loading = ref(false)

// 学生编辑弹窗
const editDialogVisible = ref(false)
const editIsEdit = ref(false)
const editFormRef = ref()
const editForm = ref<StudentRow>({
  id: '',
  student_name: '',
  name: '',
  student_no: '',
  class_id: userStore.classId ?? undefined,
})

// 积分弹窗
const scoreDialogRef = ref<InstanceType<typeof ScoreDialog> | null>(null)

async function loadStudents() {
  if (!userStore.classId) return
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('students')
      .select('*')
      .eq('class_id', userStore.classId)
      .order('student_name', { ascending: true })
    if (error) throw error

    const rows = (data ?? []) as StudentRow[]
    rows.forEach((s: any) => {
      if (!s.student_name && s.name) s.student_name = s.name
    })
    students.value = rows
  } catch (err: any) {
    ElMessage.error(err.message || '加载学生列表失败')
  } finally {
    loading.value = false
  }
}

// ===== 学生 CRUD =====
function openAddStudent() {
  editIsEdit.value = false
  editForm.value = {
    id: '',
    student_name: '',
    name: '',
    student_no: '',
    class_id: userStore.classId ?? undefined,
  }
  editDialogVisible.value = true
}

function openEditStudent(row: StudentRow) {
  editIsEdit.value = true
  editForm.value = { ...row, name: row.student_name }
  editDialogVisible.value = true
}

async function handleSubmitStudent() {
  try {
    await editFormRef.value?.validate()
  } catch {
    return
  }
  const student_name = editForm.value.student_name.trim()
  if (!student_name) {
    ElMessage.warning('请输入学生姓名')
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
        })
        .eq('id', editForm.value.id)
      if (error) throw error
      ElMessage.success('更新成功')
    } else {
      const { error } = await supabase.from('students').insert({
        student_name,
        name: student_name,
        student_no: editForm.value.student_no?.trim() || null,
        class_id: userStore.classId!,
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
    await ElMessageBox.confirm(`确定删除学生「${row.student_name || row.name}」吗？`, '提示', {
      type: 'warning',
    })
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

// ===== 积分操作 =====
function openScoreDialog(row: StudentRow, type: 'add' | 'deduct') {
  scoreDialogRef.value?.open(row, type)
}

// ===== 导出 =====
function handleExport() {
  if (students.value.length === 0) {
    ElMessage.warning('暂无学生数据可导出')
    return
  }
  const header = ['学生姓名', '学号', '总积分']
  const body = students.value.map((s) => [
    s.student_name || s.name || '',
    s.student_no || '',
    s.total_score ?? 0,
  ])
  exportToExcel([header, ...body], `学生管理_${userStore.className || ''}_${Date.now()}.xlsx`)
}

// ===== 模板下载 =====
function downloadTemplate() {
  const template = [
    ['学生姓名', '学号'],
    ['张伟', '202401'],
    ['李娜', '202402'],
  ]
  exportToExcel(template, `学生导入模板_${Date.now()}.xlsx`)
  ElMessage.success('模板已下载，填写后可批量导入')
}

// ===== 导入 =====
function handleImportClick() {
  const el = document.getElementById('student-import-file') as HTMLInputElement
  el.value = ''
  el.click()
}

async function handleFileChange(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  try {
    const buf = await file.arrayBuffer()
    const wb = XLSX.read(buf, { type: 'array' })
    const ws = wb.Sheets[wb.SheetNames[0]]
    const rows = XLSX.utils.sheet_to_json<any>(ws, { header: 1 })
    if (rows.length < 2) {
      ElMessage.warning('Excel 内容为空或只有表头')
      return
    }

    // 解析：识别表头（第一行找"姓名"或"学生姓名"）
    const header = rows[0].map((h: any) => String(h ?? '').trim())
    const nameIdx = header.findIndex((h: string) => h.includes('姓名'))
    const noIdx = header.findIndex((h: string) => h.includes('学号'))
    if (nameIdx < 0) {
      ElMessage.error('Excel 需包含"姓名"或"学生姓名"列')
      return
    }

    // upsert
    const existingMap = new Map<string, StudentRow>()
    students.value.forEach((s) => {
      if (s.student_name) existingMap.set(s.student_name.trim(), s)
    })

    let inserted = 0, updated = 0, skipped = 0
    const insertBatch: any[] = []
    const updateBatch: { id: string; patch: any }[] = []

    for (let i = 1; i < rows.length; i++) {
      const r = rows[i]
      const name = String(r[nameIdx] ?? '').trim()
      if (!name) continue
      const no = noIdx >= 0 ? String(r[noIdx] ?? '').trim() : ''

      const exist = existingMap.get(name)
      if (exist) {
        if (exist.student_no !== no) {
          updateBatch.push({
            id: exist.id,
            patch: { student_no: no || null },
          })
          updated++
        } else {
          skipped++
        }
      } else {
        insertBatch.push({
          student_name: name,
          name: name,
          student_no: no || null,
          class_id: userStore.classId!,
          school_id: userStore.schoolId || null,
          total_score: 0,
        })
        inserted++
      }
    }

    // 逐个 upsert（mock 层不支持 batch）
    for (const item of insertBatch) {
      const { error } = await supabase.from('students').insert(item)
      if (error) throw error
    }
    for (const u of updateBatch) {
      const { error } = await supabase.from('students').update(u.patch).eq('id', u.id)
      if (error) throw error
    }

    ElMessage.success(`导入完成：新增 ${inserted} 人，更新 ${updated} 人，跳过 ${skipped} 人`)
    await loadStudents()
  } catch (err: any) {
    ElMessage.error(err.message || '导入失败')
  }
}

onMounted(loadStudents)
</script>

<template>
  <el-card>
    <template #header>
      <div class="card-header">
        <span>学生管理</span>
        <div>
          <el-tag v-if="userStore.className" type="info" style="margin-right: 12px">{{ userStore.className }}</el-tag>
          <el-button @click="downloadTemplate">下载模板</el-button>
          <el-button :icon="Download" @click="handleExport">导出 Excel</el-button>
          <el-button :icon="Upload" @click="handleImportClick">批量导入</el-button>
          <input id="student-import-file" type="file" accept=".xlsx,.xls" style="display:none" @change="handleFileChange" />
          <el-button type="primary" :icon="Plus" @click="openAddStudent">新增学生</el-button>
        </div>
      </div>
    </template>

    <el-table :data="students" v-loading="loading" stripe style="width: 100%">
      <el-table-column prop="student_name" label="姓名" min-width="120">
        <template #default="{ row }">{{ row.student_name || row.name }}</template>
      </el-table-column>
      <el-table-column prop="student_no" label="学号" min-width="140">
        <template #default="{ row }">{{ row.student_no || '-' }}</template>
      </el-table-column>
      <el-table-column label="总积分" min-width="120">
        <template #default="{ row }">
          <el-tag :type="(row.total_score ?? 0) >= 0 ? 'success' : 'danger'">
            {{ row.total_score ?? 0 }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="280" fixed="right">
        <template #default="{ row }">
          <el-button link type="success" @click="openScoreDialog(row as StudentRow, 'add')">加分</el-button>
          <el-button link type="danger" @click="openScoreDialog(row as StudentRow, 'deduct')">扣分</el-button>
          <el-button link type="primary" :icon="Edit" @click="openEditStudent(row as StudentRow)" />
          <el-button link type="danger" :icon="Delete" @click="handleDeleteStudent(row as StudentRow)" />
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
      </el-form>
      <template #footer>
        <el-button @click="editDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="handleSubmitStudent">确定</el-button>
      </template>
    </el-dialog>

    <!-- 积分弹窗 -->
    <ScoreDialog ref="scoreDialogRef" @submitted="loadStudents" />
  </el-card>
</template>

<style scoped>
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
</style>
