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

/**
 * 加载本班学生列表，并兼容 name 字段补齐 student_name
 * @returns 无返回值（副作用：写入 students，并在 finally 中复位 loading）
 */
async function loadStudents() {
  if (!userStore.classId) return
  loading.value = true
  try {
    const { data: studentRows, error } = await supabase
      .from('students')
      .select('*')
      .eq('class_id', userStore.classId)
      .order('student_name', { ascending: true })
    if (error) throw error

    const studentList = (studentRows ?? []) as StudentRow[]
    studentList.forEach((student: any) => {
      if (!student.student_name && student.name) student.student_name = student.name
    })
    students.value = studentList
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载学生列表失败')
  } finally {
    loading.value = false
  }
}

// ===== 学生 CRUD =====

/**
 * 打开「新增学生」弹窗，并把表单重置为空白状态
 * @returns 无返回值（副作用：复位 editForm 与 editIsEdit，打开弹窗）
 */
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

/**
 * 打开「编辑学生」弹窗，并用当前行数据回填表单
 * @param student 表格当前行对应的学生记录
 * @returns 无返回值（副作用：回填 editForm，打开弹窗）
 */
function openEditStudent(student: StudentRow) {
  editIsEdit.value = true
  editForm.value = { ...student, name: student.student_name }
  editDialogVisible.value = true
}

/**
 * 提交学生新增/编辑表单
 * 先做表单校验，再按 editIsEdit 决定走 update 还是 insert，成功后关闭弹窗并刷新列表
 * @returns 无返回值（副作用：写入 students 表、关闭弹窗、重新加载列表）
 */
async function handleSubmitStudent() {
  try {
    await editFormRef.value?.validate()
  } catch {
    // 校验未通过时直接返回，具体错误提示由 el-form 的表单规则自行展示
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
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存失败')
  }
}

/**
 * 删除指定学生
 * 先弹确认框（用户取消则直接返回），确认后删除该学生并刷新列表
 * @param student 要删除的学生记录
 * @returns 无返回值（副作用：删除 students 表中的记录、重新加载列表）
 */
async function handleDeleteStudent(student: StudentRow) {
  try {
    await ElMessageBox.confirm(`确定删除学生「${student.student_name || student.name}」吗？`, '提示', {
      type: 'warning',
    })
  } catch {
    // 用户点了取消或关闭确认框，属于正常操作，无需提示
    return
  }
  try {
    const { error } = await supabase.from('students').delete().eq('id', student.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadStudents()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '删除失败')
  }
}

// ===== 积分操作 =====

/**
 * 打开学生积分变动弹窗（加分/扣分）
 * @param student 被操作的学生记录
 * @param type 操作类型：add 加分 / deduct 扣分
 * @returns 无返回值（副作用：调用子组件 ScoreDialog 的 open 方法）
 */
function openScoreDialog(student: StudentRow, type: 'add' | 'deduct') {
  scoreDialogRef.value?.open(student, type)
}

// ===== 导出 =====

/**
 * 导出当前班级的学生名单（姓名、学号、总积分）为 Excel
 * @returns 无返回值（副作用：下载 xlsx 文件；无数据时仅提示不导出）
 */
function handleExport() {
  if (students.value.length === 0) {
    ElMessage.warning('暂无学生数据可导出')
    return
  }
  const headerCells = ['学生姓名', '学号', '总积分']
  const bodyRows = students.value.map((student) => [
    student.student_name || student.name || '',
    student.student_no || '',
    student.total_score ?? 0,
  ])
  exportToExcel([headerCells, ...bodyRows], `学生管理_${userStore.className || ''}_${Date.now()}.xlsx`)
}

// ===== 模板下载 =====

/**
 * 下载批量导入用的 Excel 模板（含示例数据）
 * @returns 无返回值（副作用：下载 xlsx 模板文件并提示用户）
 */
function downloadTemplate() {
  const templateRows = [
    ['学生姓名', '学号'],
    ['张伟', '202401'],
    ['李娜', '202402'],
  ]
  exportToExcel(templateRows, `学生导入模板_${Date.now()}.xlsx`)
  ElMessage.success('模板已下载，填写后可批量导入')
}

// ===== 导入 =====

/**
 * 触发隐藏的文件选择框，供用户选择要导入的 Excel 文件
 * @returns 无返回值（副作用：清空 input 并触发点击）
 */
function handleImportClick() {
  const fileInput = document.getElementById('student-import-file') as HTMLInputElement
  fileInput.value = ''
  fileInput.click()
}

/**
 * 处理导入文件选择：解析 Excel 并做按姓名 upsert（已存在则更新学号，不存在则新增）
 * @param changeEvent 文件 input 的 change 事件，用于取到用户选中的文件
 * @returns 无返回值（副作用：写入/更新 students 表、提示导入结果、重新加载列表）
 */
async function handleFileChange(changeEvent: Event) {
  const fileInput = changeEvent.target as HTMLInputElement
  const file = fileInput.files?.[0]
  if (!file) return
  try {
    const fileBuffer = await file.arrayBuffer()
    const workbook = XLSX.read(fileBuffer, { type: 'array' })
    const worksheet = workbook.Sheets[workbook.SheetNames[0]]
    const sheetRows = XLSX.utils.sheet_to_json<any>(worksheet, { header: 1 })
    if (sheetRows.length < 2) {
      ElMessage.warning('Excel 内容为空或只有表头')
      return
    }

    // 解析：识别表头（第一行找"姓名"或"学生姓名"）
    const headerCells = sheetRows[0].map((cellText: any) => String(cellText ?? '').trim())
    const nameIdx = headerCells.findIndex((cellText: string) => cellText.includes('姓名'))
    const noIdx = headerCells.findIndex((cellText: string) => cellText.includes('学号'))
    if (nameIdx < 0) {
      ElMessage.error('Excel 需包含"姓名"或"学生姓名"列')
      return
    }

    // upsert
    const studentsByName = new Map<string, StudentRow>()
    students.value.forEach((student) => {
      if (student.student_name) studentsByName.set(student.student_name.trim(), student)
    })

    let insertedCount = 0, updatedCount = 0, skippedCount = 0
    const studentsToInsert: any[] = []
    const studentsToUpdate: { id: string; patch: any }[] = []

    for (let rowIndex = 1; rowIndex < sheetRows.length; rowIndex++) {
      const sheetRow = sheetRows[rowIndex]
      const studentName = String(sheetRow[nameIdx] ?? '').trim()
      if (!studentName) continue
      const studentNo = noIdx >= 0 ? String(sheetRow[noIdx] ?? '').trim() : ''

      const existingStudent = studentsByName.get(studentName)
      if (existingStudent) {
        if (existingStudent.student_no !== studentNo) {
          studentsToUpdate.push({
            id: existingStudent.id,
            patch: { student_no: studentNo || null },
          })
          updatedCount++
        } else {
          skippedCount++
        }
      } else {
        studentsToInsert.push({
          student_name: studentName,
          name: studentName,
          student_no: studentNo || null,
          class_id: userStore.classId!,
          school_id: userStore.schoolId || null,
          total_score: 0,
        })
        insertedCount++
      }
    }

    // 逐个 upsert（mock 层不支持 batch）
    for (const newStudent of studentsToInsert) {
      const { error } = await supabase.from('students').insert(newStudent)
      if (error) throw error
    }
    for (const updateItem of studentsToUpdate) {
      const { error } = await supabase.from('students').update(updateItem.patch).eq('id', updateItem.id)
      if (error) throw error
    }

    ElMessage.success(`导入完成：新增 ${insertedCount} 人，更新 ${updatedCount} 人，跳过 ${skippedCount} 人`)
    await loadStudents()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '导入失败')
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
        <template #default="{ row: studentRow }">{{ studentRow.student_name || studentRow.name }}</template>
      </el-table-column>
      <el-table-column prop="student_no" label="学号" min-width="140">
        <template #default="{ row: studentRow }">{{ studentRow.student_no || '-' }}</template>
      </el-table-column>
      <el-table-column label="总积分" min-width="120">
        <template #default="{ row: studentRow }">
          <el-tag :type="(studentRow.total_score ?? 0) >= 0 ? 'success' : 'danger'">
            {{ studentRow.total_score ?? 0 }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="280" fixed="right">
        <template #default="{ row: studentRow }">
          <el-button link type="success" @click="openScoreDialog(studentRow as StudentRow, 'add')">加分</el-button>
          <el-button link type="danger" @click="openScoreDialog(studentRow as StudentRow, 'deduct')">扣分</el-button>
          <el-button link type="primary" :icon="Edit" @click="openEditStudent(studentRow as StudentRow)" />
          <el-button link type="danger" :icon="Delete" @click="handleDeleteStudent(studentRow as StudentRow)" />
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
