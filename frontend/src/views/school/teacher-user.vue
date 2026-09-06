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

async function loadTeachers() {
  if (!userStore.schoolId) return
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, email, real_name, phone, role, school_id, class_id, class_name')
      .eq('role', 'teacher')
      .eq('school_id', userStore.schoolId)
      .order('real_name', { ascending: true })
    if (error) throw error
    teachers.value = (data ?? []) as ProfileRow[]
  } catch (err: any) {
    ElMessage.error(err.message || '加载教师列表失败')
  } finally {
    loading.value = false
  }
}

async function loadClasses() {
  if (!userStore.schoolId) return
  try {
    const { data, error } = await supabase
      .from('classes')
      .select('id, name, class_name')
      .eq('school_id', userStore.schoolId)
      .order('name', { ascending: true })
    if (error) throw error
    classes.value = (data ?? []) as ClassOpt[]
  } catch (err: any) {
    ElMessage.error(err.message || '加载班级下拉失败')
  }
}

function getClassDisplayName(c: ClassOpt | undefined | null) {
  if (!c) return ''
  return c.class_name || c.name || ''
}

function getClassName(classId?: string) {
  if (!classId) return '-'
  const c = classes.value.find((x) => x.id === classId)
  return getClassDisplayName(c) || '-'
}

function findClassByName(name: string) {
  return classes.value.find(
    (c) =>
      (c.class_name && c.class_name.trim() === name.trim()) ||
      (c.name && c.name.trim() === name.trim()),
  )
}

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
  const rows = (allClasses ?? []) as { id: string; homeroom_teacher_id: string | null }[]
  const prev = rows.find((c) => c.homeroom_teacher_id === teacherId)
  if (prev && prev.id !== newClassId) {
    await supabase.from('classes').update({ homeroom_teacher_id: null }).eq('id', prev.id)
  }
  if (newClassId) {
    await supabase.from('classes').update({ homeroom_teacher_id: teacherId }).eq('id', newClassId)
  }
  void newClassName
}

function openAdd() {
  isEdit.value = false
  form.value = { id: '', phone: '', real_name: '', class_id: '' }
  dialogVisible.value = true
}

function openEdit(row: ProfileRow) {
  isEdit.value = true
  form.value = {
    id: row.id,
    phone: row.phone ?? '',
    real_name: row.real_name ?? '',
    class_id: row.class_id ?? '',
  }
  dialogVisible.value = true
}

async function handleSubmit() {
  try {
    await formRef.value?.validate()
  } catch {
    return
  }
  try {
    const selectedClass = classes.value.find((c) => c.id === form.value.class_id)
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
      const { error } = await supabase.from('profiles').insert({
        phone: form.value.phone,
        real_name: form.value.real_name,
        role: 'teacher',
        school_id: userStore.schoolId,
        class_id: form.value.class_id || null,
        class_name: className,
      })
      if (error) throw error
      ElMessage.success('新增成功')
    }
    dialogVisible.value = false
    await loadTeachers()
  } catch (err: any) {
    ElMessage.error(err.message || '保存失败')
  }
}

async function handleDelete(row: ProfileRow) {
  try {
    await ElMessageBox.confirm(`确定删除教师「${row.real_name ?? row.email}」吗？`, '提示', {
      type: 'warning',
    })
  } catch {
    return
  }
  try {
    if (row.class_id) {
      await supabase.from('classes').update({ homeroom_teacher_id: null }).eq('id', row.class_id)
    }
    const { error } = await supabase.from('profiles').delete().eq('id', row.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadTeachers()
  } catch (err: any) {
    ElMessage.error(err.message || '删除失败')
  }
}

function handleDownloadTemplate() {
  const header = ['姓名', '手机号', '邮箱', '是否班主任', '绑定班级']
  const sample = ['王老师', '13800000001', 'teacher@demo.com', '是', '一年级一班']
  exportToExcel([header, sample], '教师导入模板.xlsx')
}

function triggerFileImport() {
  fileInputRef.value?.click()
}

function normalizeHeader(key: string): string {
  const k = String(key).trim()
  const map: Record<string, string> = {
    姓名: 'real_name', 名字: 'real_name', 名称: 'real_name',
    手机号: 'phone', 手机: 'phone', 电话: 'phone',
    邮箱: 'email', 电子邮件: 'email',
    是否班主任: 'is_homeroom', 班主任: 'is_homeroom', 是班主任: 'is_homeroom',
    绑定班级: 'bind_class', 班级: 'bind_class', 班级名: 'bind_class', 绑定班级名: 'bind_class',
  }
  return map[k] ?? k
}

async function handleFileChange(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  input.value = ''

  importLoading.value = true
  let createdCount = 0
  let updatedCount = 0
  let skippedCount = 0
  try {
    const buf = await file.arrayBuffer()
    const wb = XLSX.read(buf, { type: 'array' })
    const ws = wb.Sheets[wb.SheetNames[0]]
    const rows = XLSX.utils.sheet_to_json<any>(ws, { defval: '' })

    for (const raw of rows) {
      const mapped: Record<string, any> = {}
      for (const [k, v] of Object.entries(raw)) {
        mapped[normalizeHeader(k)] = v
      }
      const real_name = String(mapped.real_name ?? '').trim()
      const phone = String(mapped.phone ?? '').trim()
      const email = String(mapped.email ?? '').trim() || null
      const isHomeroom = ['是', 'Y', 'y', 'true', '1'].includes(
        String(mapped.is_homeroom ?? '').trim(),
      )
      const bindClassName = String(mapped.bind_class ?? '').trim()
      if (!real_name || !phone) {
        skippedCount++
        continue
      }
      const { data: existing } = await supabase
        .from('profiles')
        .select('id, class_id')
        .eq('school_id', userStore.schoolId)
        .or(`phone.eq.${phone},email.eq.${email ?? '__nope__'}`)
        .maybeSingle()

      let targetClassId: string | null = null
      let targetClassName: string | null = null
      if (isHomeroom && bindClassName) {
        const cls = findClassByName(bindClassName)
        if (!cls) {
          skippedCount++
          continue
        }
        targetClassId = cls.id
        targetClassName = getClassDisplayName(cls)
      }

      if (existing && existing.id) {
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
        await supabase.from('profiles').insert({
          phone,
          real_name,
          email,
          role: 'teacher',
          school_id: userStore.schoolId,
          class_id: targetClassId,
          class_name: targetClassName,
        })
        if (targetClassId) {
          const { data: latest } = await supabase
            .from('profiles')
            .select('id')
            .eq('school_id', userStore.schoolId)
            .eq('phone', phone)
            .maybeSingle()
          if (latest?.id) {
            await supabase
              .from('classes')
              .update({ homeroom_teacher_id: latest.id })
              .eq('id', targetClassId)
          }
        }
        createdCount++
      }
    }
    ElMessage.success(
      `批量导入完成：新增 ${createdCount} 人，更新 ${updatedCount} 人，跳过 ${skippedCount} 行`,
    )
    await loadTeachers()
  } catch (err: any) {
    ElMessage.error(err.message || '批量导入失败')
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
          <el-button link type="danger" :icon="Delete" @click="handleDelete(row as ProfileRow)">删除</el-button>
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
              v-for="c in classes"
              :key="c.id"
              :label="getClassDisplayName(c)"
              :value="c.id"
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
