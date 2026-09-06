<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Edit, Delete, Upload, Download, Trophy } from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'
import { exportToExcel } from '@/utils/excel'
import * as XLSX from 'xlsx'

const userStore = useUserStore()

interface StudentOpt {
  id: string
  student_name: string
}

interface AwardRow {
  id: string
  student_id: string
  student_name?: string
  title: string
  level: string
  award_type: string
  award_date: string
  description?: string
}

const levelOptions = ['校级', '区级', '市级', '省级', '国家级', '其他']
const typeOptions = ['获奖', '表扬', '其他']

const students = ref<StudentOpt[]>([])
const awards = ref<AwardRow[]>([])
const loading = ref(false)

const editDialogVisible = ref(false)
const editIsEdit = ref(false)
const editFormRef = ref()
const editForm = ref<AwardRow>({
  id: '',
  student_id: '',
  title: '',
  level: '校级',
  award_type: '获奖',
  award_date: new Date().toISOString().slice(0, 10),
  description: '',
})

async function loadStudents() {
  if (!userStore.classId) return
  try {
    const { data, error } = await supabase
      .from('students')
      .select('id, student_name')
      .eq('class_id', userStore.classId)
      .order('student_name', { ascending: true })
    if (error) throw error
    students.value = (data ?? []) as StudentOpt[]
  } catch (err: any) {
    ElMessage.error(err.message || '加载学生列表失败')
  }
}

async function loadAwards() {
  if (!userStore.classId) return
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('student_awards')
      .select('*')
      .order('award_date', { ascending: false })
    if (error) throw error

    const rows = (data ?? []) as AwardRow[]
    const stuMap: Record<string, string> = {}
    students.value.forEach((s) => { stuMap[s.id] = s.student_name })
    rows.forEach((r) => { if (!r.student_name) r.student_name = stuMap[r.student_id] })
    awards.value = rows
  } catch (err: any) {
    ElMessage.error(err.message || '加载获奖记录失败')
  } finally {
    loading.value = false
  }
}

function openAdd() {
  editIsEdit.value = false
  editForm.value = {
    id: '',
    student_id: '',
    title: '',
    level: '校级',
    award_type: '获奖',
    award_date: new Date().toISOString().slice(0, 10),
    description: '',
  }
  editDialogVisible.value = true
}

function openEdit(row: AwardRow) {
  editIsEdit.value = true
  editForm.value = { ...row }
  editDialogVisible.value = true
}

async function handleSubmit() {
  try {
    await editFormRef.value?.validate()
  } catch {
    return
  }
  if (!editForm.value.student_id) {
    ElMessage.warning('请选择获奖学生')
    return
  }
  try {
    const session = (await supabase.auth.getSession()).data.session
    const operatorId = session?.user.id
    if (editIsEdit.value) {
      const { error } = await supabase
        .from('student_awards')
        .update({
          student_id: editForm.value.student_id,
          title: editForm.value.title,
          level: editForm.value.level,
          award_type: editForm.value.award_type,
          award_date: editForm.value.award_date,
          description: editForm.value.description || null,
        })
        .eq('id', editForm.value.id)
      if (error) throw error
      ElMessage.success('更新成功')
    } else {
      const studentName = students.value.find((s) => s.id === editForm.value.student_id)?.student_name
      const { error } = await supabase.from('student_awards').insert({
        student_id: editForm.value.student_id,
        student_name: studentName,
        title: editForm.value.title,
        level: editForm.value.level,
        award_type: editForm.value.award_type,
        award_date: editForm.value.award_date,
        description: editForm.value.description || null,
        school_id: userStore.schoolId,
        class_id: userStore.classId,
        operator_user_id: operatorId,
      })
      if (error) throw error
      ElMessage.success('登记成功')
    }
    editDialogVisible.value = false
    await loadAwards()
  } catch (err: any) {
    ElMessage.error(err.message || '保存失败')
  }
}

async function handleDelete(row: AwardRow) {
  try {
    await ElMessageBox.confirm(`确定删除「${row.title}」获奖记录吗？`, '提示', { type: 'warning' })
  } catch {
    return
  }
  try {
    const { error } = await supabase.from('student_awards').delete().eq('id', row.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadAwards()
  } catch (err: any) {
    ElMessage.error(err.message || '删除失败')
  }
}

// ===== 模板下载 & 批量导入 =====
function downloadTemplate() {
  const wb = XLSX.utils.book_new()
  const data = [
    ['学生姓名', '获奖名称', '级别', '类型', '日期', '备注'],
    ['张三', '三好学生', '校级', '获奖', '2026-09-06', ''],
    ['李四', '数学竞赛一等奖', '区级', '获奖', '2026-09-05', ''],
  ]
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(data), '获奖记录')
  XLSX.writeFile(wb, '获奖登记模板.xlsx')
}

async function handleImport(file: File) {
  const buf = await file.arrayBuffer()
  const wb = XLSX.read(buf, { type: 'array' })
  const sheet = wb.Sheets[wb.SheetNames[0]]
  const rows = XLSX.utils.sheet_to_json(sheet, { header: 1 }) as any[][]
  const records: AwardRow[] = []

  for (let i = 1; i < rows.length; i++) {
    const row = rows[i]
    if (!row || row.length < 3) continue
    const [name, title, level, type, date, desc] = row
    if (!name || !title) continue
    const student = students.value.find((s) => s.student_name === String(name).trim())
    if (!student) {
      ElMessage.warning(`第 ${i + 1} 行：未找到学生「${name}」，已跳过`)
      continue
    }
    records.push({
      id: '',
      student_id: student.id,
      student_name: student.student_name,
      title: String(title).trim(),
      level: String(level || '校级').trim(),
      award_type: String(type || '获奖').trim(),
      award_date: date ? new Date(date).toISOString().slice(0, 10) : new Date().toISOString().slice(0, 10),
      description: desc ? String(desc).trim() : '',
    })
  }

  if (records.length === 0) {
    ElMessage.warning('没有可导入的有效记录')
    return
  }

  try {
    const session = (await supabase.auth.getSession()).data.session
    const operatorId = session?.user.id
    const { error } = await supabase.from('student_awards').insert(
      records.map((r) => ({
        student_id: r.student_id,
        student_name: r.student_name,
        title: r.title,
        level: r.level,
        award_type: r.award_type,
        award_date: r.award_date,
        description: r.description || null,
        school_id: userStore.schoolId,
        class_id: userStore.classId,
        operator_user_id: operatorId,
      })),
    )
    if (error) throw error
    ElMessage.success(`成功导入 ${records.length} 条记录`)
    await loadAwards()
  } catch (err: any) {
    ElMessage.error(err.message || '导入失败')
  }
}

function onFileChange(e: Event) {
  const target = e.target as HTMLInputElement
  const file = target.files?.[0]
  if (file) {
    handleImport(file).finally(() => { target.value = '' })
  }
}

function handleExport() {
  if (awards.value.length === 0) {
    ElMessage.warning('暂无可导出的数据')
    return
  }
  const rows = awards.value.map((r) => ({
    学生: r.student_name || '',
    获奖名称: r.title,
    级别: r.level,
    类型: r.award_type,
    日期: r.award_date,
    备注: r.description || '',
  }))
  exportToExcel(rows, `获奖记录_${Date.now()}.xlsx`)
}

onMounted(async () => {
  await loadStudents()
  await loadAwards()
})
</script>

<template>
  <el-card>
    <template #header>
      <div class="card-header">
        <div class="header-left">
          <Trophy class="header-icon" />
          <span class="header-title">获奖登记</span>
        </div>
        <div class="header-right">
          <el-button :icon="Download" @click="downloadTemplate">下载模板</el-button>
          <el-button tag="label" for="award-import" :icon="Upload">导入 Excel</el-button>
          <input id="award-import" type="file" accept=".xlsx,.xls" style="display:none" @change="onFileChange" />
          <el-button :icon="Download" @click="handleExport">导出 Excel</el-button>
          <el-button type="primary" :icon="Plus" @click="openAdd">新增登记</el-button>
        </div>
      </div>
    </template>

    <el-table :data="awards" v-loading="loading" stripe style="width: 100%">
      <el-table-column prop="student_name" label="学生" min-width="120" />
      <el-table-column prop="title" label="获奖名称" min-width="180" />
      <el-table-column prop="level" label="级别" width="100" />
      <el-table-column prop="award_type" label="类型" width="100" />
      <el-table-column prop="award_date" label="日期" min-width="140">
        <template #default="{ row }">{{ new Date(row.award_date).toLocaleDateString('zh-CN') }}</template>
      </el-table-column>
      <el-table-column prop="description" label="备注" min-width="160">
        <template #default="{ row }">{{ row.description || '-' }}</template>
      </el-table-column>
      <el-table-column label="操作" width="180" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" :icon="Edit" @click="openEdit(row as AwardRow)">编辑</el-button>
          <el-button link type="danger" :icon="Delete" @click="handleDelete(row as AwardRow)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <!-- 编辑弹窗 -->
    <el-dialog
      v-model="editDialogVisible"
      :title="editIsEdit ? '编辑获奖记录' : '新增获奖登记'"
      width="500px"
      destroy-on-close
    >
      <el-form ref="editFormRef" :model="editForm" label-width="80px">
        <el-form-item label="学生" prop="student_id" :rules="[{ required: true, message: '请选择学生', trigger: 'change' }]">
          <el-select v-model="editForm.student_id" placeholder="请选择获奖学生" filterable style="width: 100%">
            <el-option
              v-for="s in students"
              :key="s.id"
              :label="s.student_name"
              :value="s.id"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="获奖名称" prop="title" :rules="[{ required: true, message: '请输入获奖名称', trigger: 'blur' }]">
          <el-input v-model="editForm.title" placeholder="如：三好学生" maxlength="50" />
        </el-form-item>
        <el-form-item label="级别" prop="level">
          <el-select v-model="editForm.level" style="width: 100%">
            <el-option v-for="lvl in levelOptions" :key="lvl" :label="lvl" :value="lvl" />
          </el-select>
        </el-form-item>
        <el-form-item label="类型" prop="award_type">
          <el-select v-model="editForm.award_type" style="width: 100%">
            <el-option v-for="t in typeOptions" :key="t" :label="t" :value="t" />
          </el-select>
        </el-form-item>
        <el-form-item label="日期" prop="award_date">
          <el-date-picker
            v-model="editForm.award_date"
            type="date"
            value-format="YYYY-MM-DD"
            style="width: 100%"
          />
        </el-form-item>
        <el-form-item label="备注">
          <el-input v-model="editForm.description" type="textarea" :rows="2" maxlength="200" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="editDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="handleSubmit">确定</el-button>
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
.header-left {
  display: flex;
  align-items: center;
  gap: 8px;
}
.header-right {
  display: flex;
  gap: 8px;
}
.header-icon {
  font-size: 20px;
  color: #e6a23c;
}
.header-title {
  font-size: 16px;
  font-weight: 600;
}
</style>
