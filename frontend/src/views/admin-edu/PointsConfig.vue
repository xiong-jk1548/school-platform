<script setup lang="ts">
import { ElMessage, ElMessageBox } from 'element-plus'
import type { FormInstance, FormRules } from 'element-plus'
import { ref, reactive, onMounted } from 'vue'
import { supabase } from '@/api/supabase'
import { Plus, Edit, Delete, Search } from '@element-plus/icons-vue'

interface ProfileRow {
  id: string
  real_name: string
  email: string
  phone?: string
  role: string
  school_id?: string
  school_name?: string
  created_at?: string
}

interface SchoolOption {
  id: string
  name: string
}

interface AdminForm {
  id?: string
  real_name: string
  email: string
  phone: string
  school_id: string
  password?: string
}

const loading = ref(false)
const tableData = ref<ProfileRow[]>([])
const schoolOptions = ref<SchoolOption[]>([])
const searchKw = ref('')

const dialogVisible = ref(false)
const dialogTitle = ref('新增学校管理员')
const formRef = ref<FormInstance>()
const formLoading = ref(false)
const isEdit = ref(false)

const form = reactive<AdminForm>({
  real_name: '',
  email: '',
  phone: '',
  school_id: '',
  password: '',
})

const rules = reactive<FormRules<AdminForm>>({
  real_name: [{ required: true, message: '请输入真实姓名', trigger: 'blur' }],
  phone: [
    { required: true, message: '请输入手机号', trigger: 'blur' },
    { pattern: /^1[3-9]\d{9}$/, message: '手机号格式不正确', trigger: 'blur' },
  ],
  school_id: [{ required: true, message: '请选择所属学校', trigger: 'change' }],
  password: [
    {
      required: true,
      message: '请输入初始密码',
      trigger: 'blur',
    },
    { min: 6, message: '密码至少6位', trigger: 'blur' },
  ],
})

async function loadSchools() {
  const { data, error } = await supabase
    .from('schools')
    .select('id, name')
    .order('name')
  if (!error) {
    schoolOptions.value = (data ?? []) as SchoolOption[]
  }
}

async function loadData() {
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select(
        `id, real_name, email, phone, role, school_id, created_at,
         schools(id, name)`,
      )
      .eq('role', 'school_admin')
      .order('created_at', { ascending: false })
    if (error) throw error
    tableData.value = ((data ?? []) as any[]).map((row) => ({
      id: row.id,
      real_name: row.real_name ?? '',
      email: row.email ?? '',
      phone: row.phone ?? '',
      role: row.role,
      school_id: row.school_id,
      school_name: row.schools?.name ?? '-',
      created_at: row.created_at,
    }))
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '加载列表失败')
  } finally {
    loading.value = false
  }
}

function openAdd() {
  isEdit.value = false
  dialogTitle.value = '新增学校管理员'
  Object.assign(form, {
    real_name: '',
    email: '',
    phone: '',
    school_id: '',
    password: 'Admin@123',
  })
  dialogVisible.value = true
}

function openEdit(row: ProfileRow) {
  isEdit.value = true
  dialogTitle.value = '编辑学校管理员'
  Object.assign(form, {
    id: row.id,
    real_name: row.real_name,
    email: row.email,
    phone: row.phone ?? '',
    school_id: row.school_id ?? '',
    password: '',
  })
  dialogVisible.value = true
}

async function handleSubmit() {
  const valid = await formRef.value?.validate().catch(() => false)
  if (!valid) return
  formLoading.value = true
  try {
    if (isEdit.value && form.id) {
      const { error } = await supabase
        .from('profiles')
        .update({
          real_name: form.real_name,
          phone: form.phone || null,
          school_id: form.school_id,
        })
        .eq('id', form.id)
      if (error) throw error
      ElMessage.success('更新成功')
    } else {
      await createSchoolAdmin()
    }
    dialogVisible.value = false
    await loadData()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '保存失败')
  } finally {
    formLoading.value = false
  }
}

async function createSchoolAdmin() {
  try {
    const { error: rpcErr } = await supabase.rpc(
      'create_school_admin',
      {
        p_phone: form.phone,
        p_password: form.password,
        p_real_name: form.real_name,
        p_email: form.email || null,
        p_school_id: form.school_id,
      },
    )
    if (!rpcErr) {
      ElMessage.success('学校管理员创建成功')
      return
    }
  } catch {
    /* rpc 不存在，走 fallback */
  }

  const { data, error } = await supabase.auth.signUp({
    email: form.email || form.phone + '@demo.local',
    password: form.password!,
    options: {
      data: {
        role: 'school_admin',
        name: form.real_name,
        phone: form.phone,
        school_id: form.school_id,
      },
    },
  })
  if (error) throw error
  if (!data.user) throw new Error('创建用户失败')

  const { error: profErr } = await supabase.from('profiles').insert({
    id: data.user.id,
    email: form.email || null,
    phone: form.phone,
    real_name: form.real_name,
    role: 'school_admin',
    school_id: form.school_id,
  })
  if (profErr) throw profErr

  ElMessage.success('学校管理员创建成功')
}

async function handleDelete(row: ProfileRow) {
  try {
    await ElMessageBox.confirm(
      `确定要删除学校管理员「${row.real_name || row.email}」吗？`,
      '危险操作',
      { type: 'error', confirmButtonText: '删除' },
    )
    const { error } = await supabase.from('profiles').delete().eq('id', row.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadData()
  } catch (err: unknown) {
    if (err !== 'cancel') {
      ElMessage.error(err instanceof Error ? err.message : '删除失败')
    }
  }
}

onMounted(async () => {
  await loadSchools()
  await loadData()
})
</script>

<template>
  <div class="page">
    <el-alert
      type="info"
      :closable="false"
      show-icon
      title="创建学校管理员会自动在 auth.users 创建账号，并初始化 profile 记录。新账号初始密码为 Admin@123，请通知用户首次登录后修改。"
      style="margin-bottom: 16px"
    />

    <el-card shadow="never">
      <div class="toolbar">
        <div class="toolbar-left">
          <el-input
            v-model="searchKw"
            placeholder="搜索姓名或邮箱"
            :prefix-icon="Search"
            clearable
            style="width: 260px"
          />
        </div>
        <el-button type="primary" :icon="Plus" @click="openAdd">新增学校管理员</el-button>
      </div>

      <el-table
        :data="
          tableData.filter(
            (u) =>
              !searchKw ||
              u.real_name.toLowerCase().includes(searchKw.toLowerCase()) ||
              u.email.toLowerCase().includes(searchKw.toLowerCase()),
          )
        "
        v-loading="loading"
        stripe
      >
        <el-table-column prop="real_name" label="真实姓名" min-width="120" />
        <el-table-column prop="email" label="邮箱" min-width="180" />
        <el-table-column prop="phone" label="手机号" width="140" />
        <el-table-column prop="school_name" label="所属学校" min-width="160" />
        <el-table-column label="角色" width="120">
          <template #default>
            <el-tag type="warning" effect="light">学校管理员</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="created_at" label="创建时间" width="180">
          <template #default="{ row }">
            {{ row.created_at ? new Date(row.created_at).toLocaleString() : '-' }}
          </template>
        </el-table-column>
        <el-table-column label="操作" width="180" fixed="right" align="center">
          <template #default="{ row }">
            <el-button link type="primary" :icon="Edit" @click="openEdit(row as ProfileRow)">
              编辑
            </el-button>
            <el-button
              link
              type="danger"
              :icon="Delete"
              @click="handleDelete(row as ProfileRow)"
            >
              删除
            </el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-dialog
      v-model="dialogVisible"
      :title="dialogTitle"
      width="520px"
      :close-on-click-modal="false"
    >
      <el-form
        ref="formRef"
        :model="form"
        :rules="rules"
        label-width="90px"
      >
        <el-form-item label="真实姓名" prop="real_name">
          <el-input v-model="form.real_name" placeholder="请输入真实姓名" />
        </el-form-item>
        <el-form-item label="手机号" prop="phone">
          <el-input
            v-model="form.phone"
            placeholder="用于登录的手机号"
            :disabled="isEdit"
          />
        </el-form-item>
        <el-form-item label="邮箱">
          <el-input v-model="form.email" placeholder="选填" />
        </el-form-item>
        <el-form-item label="所属学校" prop="school_id">
          <el-select
            v-model="form.school_id"
            placeholder="请选择学校"
            style="width: 100%"
          >
            <el-option
              v-for="s in schoolOptions"
              :key="s.id"
              :value="s.id"
              :label="s.name"
            />
          </el-select>
        </el-form-item>
        <el-form-item
          v-if="!isEdit"
          label="初始密码"
          prop="password"
        >
          <el-input
            v-model="form.password"
            show-password
            placeholder="至少6位"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="formLoading" @click="handleSubmit">
          确定
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.page {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
}
</style>
