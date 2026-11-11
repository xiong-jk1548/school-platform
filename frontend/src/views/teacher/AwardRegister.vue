<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'
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

/**
 * 加载本班学生列表（供「获奖登记」的学生下拉框使用）
 * @returns 无返回值，成功后写入 students 列表
 */
async function loadStudents() {
  if (!userStore.classId) return
  try {
    const { data: studentRows, error } = await supabase
      .from('students')
      .select('id, student_name')
      .eq('class_id', userStore.classId)
      .order('student_name', { ascending: true })
    if (error) throw error
    students.value = (studentRows ?? []) as StudentOpt[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载学生列表失败')
  }
}

/**
 * 加载本班获奖记录列表，并补齐 student_name
 * ⚠️ 必须显式按 class_id 收窄：`student_awards` 的教师读取策略是**按学校**放行的
 *（同一张表在 09 脚本里给 teacher 的是 school_id 粒度，与 student_scores 的 class_id 粒度不同），
 * 而本页是"班级获奖登记"。漏掉这个过滤条件就会出现获奖记录串班 —— DEPLOY-LESSONS 第 19 条
 * 记的就是这个现象，但当时只补了注释、查询并未真正加过滤，所以又被复现了一次。
 * @returns 无返回值，成功后写入 awards 列表，并在 finally 中复位 loading
 */
async function loadAwards() {
  if (!userStore.classId) return
  loading.value = true
  try {
    const { data: awardRows, error } = await supabase
      .from('student_awards')
      .select('*')
      .eq('class_id', userStore.classId)
      .order('award_date', { ascending: false })
    if (error) throw error

    const awardRecords = (awardRows ?? []) as AwardRow[]
    const stuMap: Record<string, string> = {}
    students.value.forEach((student) => { stuMap[student.id] = student.student_name })
    awardRecords.forEach((award) => { if (!award.student_name) award.student_name = stuMap[award.student_id] })
    awards.value = awardRecords
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载获奖记录失败')
  } finally {
    loading.value = false
  }
}

/**
 * 打开「新增获奖登记」弹窗，并把表单重置为初始值
 */
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

/**
 * 打开编辑弹窗，把待编辑记录回填到表单
 * @param award 表格当前行的获奖记录
 */
function openEdit(award: AwardRow) {
  editIsEdit.value = true
  editForm.value = { ...award }
  editDialogVisible.value = true
}

/**
 * 提交获奖登记表单：按 editIsEdit 决定新增还是更新，成功后刷新列表
 * @returns 无返回值（副作用：写库、关闭弹窗、刷新 awards）
 */
async function handleSubmit() {
  try {
    await editFormRef.value?.validate()
  } catch {
    // 表单校验未通过，错误提示由 el-form 自行展示，此处直接返回
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
      const studentName = students.value.find((student) => student.id === editForm.value.student_id)?.student_name
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
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存失败')
  }
}

/**
 * 删除一条获奖记录（先二次确认，用户取消则直接返回）
 * @param award 表格当前行的获奖记录
 */
async function handleDelete(award: AwardRow) {
  try {
    await ElMessageBox.confirm(`确定删除「${award.title}」获奖记录吗？`, '提示', { type: 'warning' })
  } catch {
    // 用户在确认框中点了「取消」，此处静默返回即可
    return
  }
  try {
    const { error } = await supabase.from('student_awards').delete().eq('id', award.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadAwards()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '删除失败')
  }
}

// ===== 模板下载 & 批量导入 =====
/**
 * 下载获奖登记 Excel 模板（含两行示例数据，表头为姓名/名称/级别/类型/日期/备注）
 */
function downloadTemplate() {
  const workbook = XLSX.utils.book_new()
  const templateRows = [
    ['学生姓名', '获奖名称', '级别', '类型', '日期', '备注'],
    ['张三', '三好学生', '校级', '获奖', '2026-09-06', ''],
    ['李四', '数学竞赛一等奖', '区级', '获奖', '2026-09-05', ''],
  ]
  XLSX.utils.book_append_sheet(workbook, XLSX.utils.aoa_to_sheet(templateRows), '获奖记录')
  XLSX.writeFile(workbook, '获奖登记模板.xlsx')
}

/**
 * 解析 Excel 并批量写入获奖记录
 * 第 1 行为表头，逐行按「学生姓名」匹配本班学生；匹配不到的行跳过并提示行号
 * @param file 用户在文件选择框选中的 xlsx/xls 文件
 * @returns 无返回值（副作用：写库、消息提示、刷新 awards）
 */
async function handleImport(file: File) {
  const fileBuffer = await file.arrayBuffer()
  const workbook = XLSX.read(fileBuffer, { type: 'array' })
  const worksheet = workbook.Sheets[workbook.SheetNames[0]]
  const sheetRows = XLSX.utils.sheet_to_json(worksheet, { header: 1 }) as any[][]
  const awardRecords: AwardRow[] = []

  for (let rowIndex = 1; rowIndex < sheetRows.length; rowIndex++) {
    const sheetRow = sheetRows[rowIndex]
    if (!sheetRow || sheetRow.length < 3) continue
    const [name, title, level, type, date, desc] = sheetRow
    if (!name || !title) continue
    const student = students.value.find((candidate) => candidate.student_name === String(name).trim())
    if (!student) {
      ElMessage.warning(`第 ${rowIndex + 1} 行：未找到学生「${name}」，已跳过`)
      continue
    }
    awardRecords.push({
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

  if (awardRecords.length === 0) {
    ElMessage.warning('没有可导入的有效记录')
    return
  }

  try {
    const session = (await supabase.auth.getSession()).data.session
    const operatorId = session?.user.id
    const { error } = await supabase.from('student_awards').insert(
      awardRecords.map((award) => ({
        student_id: award.student_id,
        student_name: award.student_name,
        title: award.title,
        level: award.level,
        award_type: award.award_type,
        award_date: award.award_date,
        description: award.description || null,
        school_id: userStore.schoolId,
        class_id: userStore.classId,
        operator_user_id: operatorId,
      })),
    )
    if (error) throw error
    ElMessage.success(`成功导入 ${awardRecords.length} 条记录`)
    await loadAwards()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '导入失败')
  }
}

/**
 * 文件选择框的 change 事件处理：取到文件后交给批量导入，并在完成后清空 input
 * @param changeEvent input 元素的 change 事件
 */
function onFileChange(changeEvent: Event) {
  const fileInput = changeEvent.target as HTMLInputElement
  const file = fileInput.files?.[0]
  if (file) {
    handleImport(file).finally(() => { fileInput.value = '' })
  }
}

/**
 * 导出当前获奖记录列表为 Excel
 */
function handleExport() {
  if (awards.value.length === 0) {
    ElMessage.warning('暂无可导出的数据')
    return
  }
  const exportRows = awards.value.map((award) => ({
    学生: award.student_name || '',
    获奖名称: award.title,
    级别: award.level,
    类型: award.award_type,
    日期: award.award_date,
    备注: award.description || '',
  }))
  exportToExcel(exportRows, `获奖记录_${Date.now()}.xlsx`)
}

/**
 * 顶栏班级下拉切换后跟随重载学生与获奖记录。
 * 本页在挂载时按当时的班级加载，若不跟随切换，页面标题已换成新班级但列表仍是旧班级的数据。
 * @param classId 当前选中班级 id
 * @returns 无返回值
 */
watch(() => userStore.classId, async (classId, previousClassId) => {
  if (classId === previousClassId) return
  awards.value = []
  students.value = []
  await loadStudents()
  await loadAwards()
})

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
        <template #default="{ row: awardRow }">{{ new Date(awardRow.award_date).toLocaleDateString('zh-CN') }}</template>
      </el-table-column>
      <el-table-column prop="description" label="备注" min-width="160">
        <template #default="{ row: awardRow }">{{ awardRow.description || '-' }}</template>
      </el-table-column>
      <el-table-column label="操作" width="180" fixed="right">
        <template #default="{ row: awardRow }">
          <el-button link type="primary" :icon="Edit" @click="openEdit(awardRow as AwardRow)">编辑</el-button>
          <el-button link type="danger" :icon="Delete" @click="handleDelete(awardRow as AwardRow)">删除</el-button>
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
              v-for="student in students"
              :key="student.id"
              :label="student.student_name"
              :value="student.id"
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
            <el-option v-for="awardType in typeOptions" :key="awardType" :label="awardType" :value="awardType" />
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
