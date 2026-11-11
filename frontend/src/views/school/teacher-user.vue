<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Edit, Delete, Download, Upload } from '@element-plus/icons-vue'
import * as XLSX from 'xlsx'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'
import { exportToExcel } from '@/utils/excel'

const userStore = useUserStore()

interface ProfileRow {
  id: string
  email?: string
  real_name?: string
  phone?: string
  role?: string
  school_id?: string
  class_id?: string
  class_name?: string
}

interface ClassOpt {
  id: string
  name: string
  class_name?: string
}

const teachers = ref<ProfileRow[]>([])
const classes = ref<ClassOpt[]>([])
const loading = ref(false)
const importLoading = ref(false)

const dialogVisible = ref(false)
const isEdit = ref(false)
const formRef = ref()
const fileInputRef = ref<HTMLInputElement | null>(null)
const form = ref<{
  id: string
  phone: string
  real_name: string
  class_id: string
}>({ id: '', phone: '', real_name: '', class_id: '' })

/**
 * 加载本校教师账号列表（含学科教师与学校管理员）。
 * @returns 无返回值，结果写入响应式变量 teachers
 */
async function loadTeachers() {
  if (!userStore.schoolId) return
  loading.value = true
  try {
    const { data: teacherData, error } = await supabase
      .from('profiles')
      .select('id, email, real_name, phone, role, school_id, class_id, class_name')
      .in('role', ['teacher', 'school_admin'])
      .eq('school_id', userStore.schoolId)
      .order('real_name', { ascending: true })
    if (error) throw error
    teachers.value = (teacherData ?? []) as ProfileRow[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载教师列表失败')
  } finally {
    loading.value = false
  }
}

/**
 * 加载本校班级列表，用于「绑定班级」下拉与班级名反查。
 * @returns 无返回值，结果写入响应式变量 classes
 */
async function loadClasses() {
  if (!userStore.schoolId) return
  try {
    const { data: classData, error } = await supabase
      .from('classes')
      .select('id, name, class_name')
      .eq('school_id', userStore.schoolId)
      .order('name', { ascending: true })
    if (error) throw error
    classes.value = (classData ?? []) as ClassOpt[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载班级下拉失败')
  }
}

/**
 * 取班级显示名，优先使用 class_name，回退 name。
 * @param classItem 班级对象，可能为空
 * @returns 班级显示名；无数据时返回空字符串
 */
function getClassDisplayName(classItem: ClassOpt | undefined | null) {
  if (!classItem) return ''
  return classItem.class_name || classItem.name || ''
}

/**
 * 按班级 id 查班级显示名（教师列表「绑定班级」列使用）。
 * @param classId 班级 id，可为空
 * @returns 班级显示名；空值或未匹配时返回 '-'
 */
function getClassName(classId?: string) {
  if (!classId) return '-'
  const matchedClass = classes.value.find((classItem) => classItem.id === classId)
  return getClassDisplayName(matchedClass) || '-'
}

/**
 * 按班级名称在本校班级列表中查找班级（用于 Excel 导入的「绑定班级」列）。
 * @param name 班级名称（与 class_name 或 name 完全匹配，忽略首尾空格）
 * @returns 命中的班级对象；未命中返回 undefined
 */
function findClassByName(name: string) {
  return classes.value.find(
    (classItem) =>
      (classItem.class_name && classItem.class_name.trim() === name.trim()) ||
      (classItem.name && classItem.name.trim() === name.trim()),
  )
}

/**
 * 同步「班主任」关系：先解除该教师原先担任班主任的班级，再绑定到新班级。
 * 教师的班级归属（profiles.class_id / class_name）由调用方按需写入。
 * @param teacherId 教师 profile id
 * @param newClassId 新的班主任班级 id，null 表示不绑定
 * @param newClassName 新的班主任班级名（由调用方维护，本函数不写库）
 * @returns Promise，写入 classes.homeroom_teacher_id
 */
async function syncClassHomeroomTeacher(
  teacherId: string,
  newClassId: string | null,
  newClassName: string | null,
) {
  if (!userStore.schoolId) return
  const { data: allClasses, error } = await supabase
    .from('classes')
    .select('id, homeroom_teacher_id')
    .eq('school_id', userStore.schoolId)
  if (error) throw error
  const allClassRows = (allClasses ?? []) as { id: string; homeroom_teacher_id: string | null }[]
  const previousHomeroomClass = allClassRows.find((classItem) => classItem.homeroom_teacher_id === teacherId)
  if (previousHomeroomClass && previousHomeroomClass.id !== newClassId) {
    await supabase.from('classes').update({ homeroom_teacher_id: null }).eq('id', previousHomeroomClass.id)
  }
  if (newClassId) {
    await supabase.from('classes').update({ homeroom_teacher_id: teacherId }).eq('id', newClassId)
  }
  void newClassName
}

/**
 * 打开「新增教师」弹窗，并重置表单。
 * @returns 无返回值，直接控制弹窗与表单状态
 */
function openAdd() {
  isEdit.value = false
  form.value = { id: '', phone: '', real_name: '', class_id: '' }
  dialogVisible.value = true
}

/**
 * 打开「编辑教师」弹窗，用选中教师的数据回填表单。
 * @param teacherRow 被编辑的教师行（profiles 记录）
 * @returns 无返回值，直接控制弹窗与表单状态
 */
function openEdit(teacherRow: ProfileRow) {
  isEdit.value = true
  form.value = {
    id: teacherRow.id,
    phone: teacherRow.phone ?? '',
    real_name: teacherRow.real_name ?? '',
    class_id: teacherRow.class_id ?? '',
  }
  dialogVisible.value = true
}

/**
 * 提交新增/编辑教师。
 * 新增走 create_teacher RPC（同时创建登录账号与 profiles 档案），编辑只更新班级绑定并同步班主任关系。
 * @returns 无返回值，成功后刷新教师列表
 */
async function handleSubmit() {
  try {
    await formRef.value?.validate()
  } catch {
    // 表单校验未通过（Element Plus 已给出提示），直接中断提交
    return
  }
  try {
    const selectedClass = classes.value.find((classItem) => classItem.id === form.value.class_id)
    const className = form.value.class_id ? getClassDisplayName(selectedClass) || null : null
    if (isEdit.value) {
      const { error } = await supabase
        .from('profiles')
        .update({
          class_id: form.value.class_id || null,
          class_name: className,
        })
        .eq('id', form.value.id)
      if (error) throw error
      await syncClassHomeroomTeacher(form.value.id, form.value.class_id || null, className)
      ElMessage.success('更新成功')
    } else {
      // 先走 RPC create_teacher（自动创建 auth.users + profiles）
      const rpcResponse = await supabase.rpc('create_teacher', {
        p_phone: form.value.phone || null,
        p_password: '123456',
        p_real_name: form.value.real_name,
        p_email: null,
        p_school_id: userStore.schoolId,
        p_class_id: form.value.class_id || null,
      })
      if (rpcResponse.error) throw rpcResponse.error
      ElMessage.success('新增成功（默认密码 123456）')
    }
    dialogVisible.value = false
    await loadTeachers()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存失败')
  }
}

/**
 * 删除教师账号。学校管理员账号不允许在此删除（会影响登录），会先给出提示。
 * @param teacherRow 被删除的教师行（profiles 记录）
 * @returns 无返回值，成功后刷新教师列表
 */
async function handleDelete(teacherRow: ProfileRow) {
  if (teacherRow.role === 'school_admin') {
    ElMessage.warning('学校管理员账号不支持在此删除（会影响登录）')
    return
  }
  try {
    await ElMessageBox.confirm(`确定删除教师「${teacherRow.real_name ?? teacherRow.email}」吗？`, '提示', {
      type: 'warning',
    })
  } catch {
    // 用户在确认框点了取消，不执行删除
    return
  }
  try {
    if (teacherRow.class_id) {
      await supabase.from('classes').update({ homeroom_teacher_id: null }).eq('id', teacherRow.class_id)
    }
    const { error } = await supabase.from('profiles').delete().eq('id', teacherRow.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadTeachers()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '删除失败')
  }
}

/**
 * 下载教师导入 Excel 模板（姓名/手机号/密码/邮箱/是否班主任/绑定班级六列）。
 * @returns 无返回值，直接触发浏览器下载
 */
function handleDownloadTemplate() {
  const header = ['姓名', '手机号', '密码', '邮箱', '是否班主任', '绑定班级']
  const sample = ['王老师', '13800000001', '123456', '', '是', '一年级一班']
  exportToExcel([header, sample], '教师导入模板.xlsx')
}

/** 触发隐藏的 file input，打开文件选择框 */
function triggerFileImport() {
  fileInputRef.value?.click()
}

/**
 * 把 Excel 表头（中文）归一化为内部字段名，便于后续按字段取值。
 * 未登记的列名原样返回。
 * @param key Excel 原始表头
 * @returns 内部字段名（如 real_name / phone / bind_class）
 */
function normalizeHeader(key: string): string {
  const rawHeader = String(key).trim()
  const headerAliasMap: Record<string, string> = {
    姓名: 'real_name', 名字: 'real_name', 名称: 'real_name',
    手机号: 'phone', 手机: 'phone', 电话: 'phone',
    密码: 'password', 初始密码: 'password',
    邮箱: 'email', 电子邮件: 'email',
    是否班主任: 'is_homeroom', 班主任: 'is_homeroom', 是班主任: 'is_homeroom',
    绑定班级: 'bind_class', 班级: 'bind_class', 班级名: 'bind_class', 绑定班级名: 'bind_class',
  }
  return headerAliasMap[rawHeader] ?? rawHeader
}

/**
 * 批量导入教师：逐行解析 Excel，已存在的档案更新班级绑定，不存在的走 create_teacher RPC 新建账号。
 * 每行独立处理，单行失败只记录到 errorRows 并计入跳过数，不中断整体导入。
 * @param event 文件选择框的 change 事件
 * @returns 无返回值，结束后提示新增/更新/跳过统计并刷新教师列表
 */
async function handleFileChange(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  input.value = ''

  importLoading.value = true
  let createdCount = 0
  let updatedCount = 0
  let skippedCount = 0
  const errorRows: string[] = []
  try {
    const buf = await file.arrayBuffer()
    const wb = XLSX.read(buf, { type: 'array' })
    const ws = wb.Sheets[wb.SheetNames[0]]
    const sheetRows = XLSX.utils.sheet_to_json<any>(ws, { defval: '' })

    for (const excelRow of sheetRows) {
      const normalizedRow: Record<string, any> = {}
      for (const [excelHeader, excelValue] of Object.entries(excelRow)) {
        normalizedRow[normalizeHeader(excelHeader)] = excelValue
      }
      const real_name = String(normalizedRow.real_name ?? '').trim()
      const phone = String(normalizedRow.phone ?? '').trim()
      const email = String(normalizedRow.email ?? '').trim() || null
      const password = String(normalizedRow.password ?? '').trim() || '123456'
      const isHomeroom = ['是', 'Y', 'y', 'true', '1'].includes(
        String(normalizedRow.is_homeroom ?? '').trim(),
      )
      const bindClassName = String(normalizedRow.bind_class ?? '').trim()
      if (!real_name || !phone) {
        skippedCount++
        continue
      }

      let targetClassId: string | null = null
      let targetClassName: string | null = null
      if (isHomeroom && bindClassName) {
        const cls = findClassByName(bindClassName)
        if (!cls) {
          errorRows.push(`${real_name}：班级「${bindClassName}」不存在，已跳过`)
          skippedCount++
          continue
        }
        targetClassId = cls.id
        targetClassName = getClassDisplayName(cls)
      }

      const { data: existing } = await supabase
        .from('profiles')
        .select('id, class_id')
        .eq('school_id', userStore.schoolId)
        .or(`phone.eq.${phone},email.eq.${email ?? '__nope__'}`)
        .maybeSingle()

      if (existing && existing.id) {
        // 已存在：更新档案（school_admin 有本校 profiles 写权限）
        await supabase
          .from('profiles')
          .update({
            real_name,
            email,
            class_id: targetClassId,
            class_name: targetClassName,
          })
          .eq('id', existing.id)
        if (targetClassId) {
          await syncClassHomeroomTeacher(existing.id, targetClassId, targetClassName)
        }
        updatedCount++
      } else {
        // 新增：走 create_teacher RPC（同时创建 auth.users 登录账号 + profiles）
        const rpcResponse = await supabase.rpc('create_teacher', {
          p_phone: phone,
          p_password: password,
          p_real_name: real_name,
          p_email: email,
          p_school_id: userStore.schoolId,
          p_class_id: targetClassId,
        })
        if (rpcResponse.error) {
          errorRows.push(`${real_name}：${rpcResponse.error.message}`)
          skippedCount++
          continue
        }
        // 班主任：把班级 homeroom_teacher_id 指向新老师
        const createdTeacherId = (rpcResponse.data as any)?.user_id
        if (targetClassId && createdTeacherId) {
          await supabase
            .from('classes')
            .update({ homeroom_teacher_id: createdTeacherId })
            .eq('id', targetClassId)
        }
        createdCount++
      }
    }
    let msg = `批量导入完成：新增 ${createdCount} 人，更新 ${updatedCount} 人，跳过 ${skippedCount} 行`
    if (errorRows.length) msg += `\n${errorRows.slice(0, 5).join('\n')}`
    ElMessage({ type: createdCount || updatedCount ? 'success' : 'warning', message: msg, duration: 6000 })
    await loadTeachers()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '批量导入失败')
  } finally {
    importLoading.value = false
  }
}

const dialogTitle = computed(() => (isEdit.value ? '编辑教师' : '新增教师'))

onMounted(async () => {
  await Promise.all([loadClasses(), loadTeachers()])
})
</script>

<template>
  <el-card>
    <template #header>
      <div class="card-header">
        <span>本校教师账号管理</span>
        <div class="header-actions">
          <el-button :icon="Download" @click="handleDownloadTemplate">下载模板</el-button>
          <el-button :icon="Upload" :loading="importLoading" @click="triggerFileImport">批量导入</el-button>
          <input
            ref="fileInputRef"
            type="file"
            accept=".xlsx,.xls"
            style="display: none"
            @change="handleFileChange"
          />
          <el-button type="primary" :icon="Plus" @click="openAdd">新增教师</el-button>
        </div>
      </div>
    </template>

    <el-table :data="teachers" v-loading="loading" stripe style="width: 100%">
      <el-table-column prop="real_name" label="姓名" min-width="120" />
      <el-table-column prop="email" label="邮箱" min-width="180" />
      <el-table-column prop="phone" label="手机" min-width="140">
        <template #default="{ row }">{{ row.phone || '-' }}</template>
      </el-table-column>
      <el-table-column label="角色" min-width="130">
        <template #default="{ row }">
          <el-tag v-if="row.class_id" type="warning" effect="light">
            班主任 · {{ getClassName(row.class_id) }}
          </el-tag>
          <el-tag v-else type="info" effect="light">学科教师</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="绑定班级" min-width="160">
        <template #default="{ row }">{{ getClassName(row.class_id) }}</template>
      </el-table-column>
      <el-table-column label="操作" width="180" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" :icon="Edit" @click="openEdit(row as ProfileRow)">编辑</el-button>
          <el-button
            v-if="row.role !== 'school_admin'"
            link
            type="danger"
            :icon="Delete"
            @click="handleDelete(row as ProfileRow)"
          >删除</el-button>
          <el-tag v-else type="info" size="small">管理员账号</el-tag>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="dialogVisible" :title="dialogTitle" width="460px" destroy-on-close>
      <el-form ref="formRef" :model="form" label-width="90px">
        <el-form-item
          v-if="!isEdit"
          label="手机号"
          prop="phone"
          :rules="[{ required: true, message: '请输入手机号', trigger: 'blur' }, { pattern: /^1[3-9]\d{9}$/, message: '手机号格式不正确', trigger: 'blur' }]"
        >
          <el-input v-model="form.phone" placeholder="用于登录的手机号" />
        </el-form-item>
        <el-form-item
          v-if="!isEdit"
          label="姓名"
          prop="real_name"
          :rules="[{ required: true, message: '请输入姓名', trigger: 'blur' }]"
        >
          <el-input v-model="form.real_name" placeholder="真实姓名" />
        </el-form-item>
        <el-form-item label="绑定班级">
          <el-select v-model="form.class_id" placeholder="未绑定" clearable style="width: 100%">
            <el-option
              v-for="classOption in classes"
              :key="classOption.id"
              :label="getClassDisplayName(classOption)"
              :value="classOption.id"
            />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
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
.header-actions {
  display: flex;
  gap: 8px;
  align-items: center;
}
</style>
