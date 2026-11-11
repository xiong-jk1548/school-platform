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

/**
 * 加载「所属学校」下拉选项，只取学校 id 与名称并按名称排序。
 * @returns 无返回值，选项写入 schoolOptions
 */
async function loadSchools() {
  const { data: schoolRows, error } = await supabase
    .from('schools')
    .select('id, name')
    .order('name')
  if (!error) {
    schoolOptions.value = (schoolRows ?? []) as SchoolOption[]
  }
}

/**
 * 加载学校管理员列表，并联表 schools 取出所属学校名称。
 * @returns 无返回值，列表写入 tableData
 */
async function loadData() {
  loading.value = true
  try {
    const { data: profileRows, error } = await supabase
      .from('profiles')
      .select(
        `id, real_name, email, phone, role, school_id, created_at,
         schools(id, name)`,
      )
      .eq('role', 'school_admin')
      .order('created_at', { ascending: false })
    if (error) throw error
    // 坑：所属学校一列曾直接渲染 school_id，界面上显示成一串 UUID，
    // 这里改为联表取 schools.name 展示（见“学校列表显示 UUID”那次排查）
    tableData.value = ((profileRows ?? []) as any[]).map((profile) => ({
      id: profile.id,
      real_name: profile.real_name ?? '',
      email: profile.email ?? '',
      phone: profile.phone ?? '',
      role: profile.role,
      school_id: profile.school_id,
      school_name: profile.schools?.name ?? '-',
      created_at: profile.created_at,
    }))
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '加载列表失败')
  } finally {
    loading.value = false
  }
}

/**
 * 打开「新增学校管理员」弹窗，并把表单重置为默认初始密码。
 * @returns 无返回值，仅切换弹窗状态
 */
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

/**
 * 打开「编辑学校管理员」弹窗，用选中记录回填表单（编辑态不允许改手机号）。
 * @param profile 表格中选中的管理员记录
 * @returns 无返回值，仅切换弹窗状态
 */
function openEdit(profile: ProfileRow) {
  isEdit.value = true
  dialogTitle.value = '编辑学校管理员'
  Object.assign(form, {
    id: profile.id,
    real_name: profile.real_name,
    email: profile.email,
    phone: profile.phone ?? '',
    school_id: profile.school_id ?? '',
    password: '',
  })
  dialogVisible.value = true
}

/**
 * 提交弹窗表单：编辑态直接更新 profiles，新增态交给 createSchoolAdmin 处理。
 * @returns 无返回值，成功后关闭弹窗并刷新列表
 */
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

/**
 * 新增学校管理员：优先调用 create_school_admin RPC（由数据库完成 auth 账号创建与去重），
 * RPC 不可用时回退为「signUp 建号 + 写入 profiles」的旧流程。
 * @returns 无返回值，创建失败时抛出异常交由调用方提示
 */
async function createSchoolAdmin() {
  try {
    // 坑：直接建 auth 账号时 phone/email 重复会返回 409，
    // 改走 create_school_admin RPC 由数据库侧自动去重（见“新增学校管理员 409”那次排查）
    const { error: rpcError } = await supabase.rpc(
      'create_school_admin',
      {
        p_phone: form.phone,
        p_password: form.password,
        p_real_name: form.real_name,
        p_email: form.email || null,
        p_school_id: form.school_id,
      },
    )
    if (!rpcError) {
      ElMessage.success('学校管理员创建成功')
      return
    }
  } catch {
    /* rpc 不存在，走 fallback */
  }

  const { data: signUpData, error } = await supabase.auth.signUp({
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
  if (!signUpData.user) throw new Error('创建用户失败')

  const { error: profErr } = await supabase.from('profiles').insert({
    id: signUpData.user.id,
    email: form.email || null,
    phone: form.phone,
    real_name: form.real_name,
    role: 'school_admin',
    school_id: form.school_id,
  })
  if (profErr) throw profErr

  ElMessage.success('学校管理员创建成功')
}

/**
 * 删除学校管理员：先二次确认，再从 profiles 中删除该记录。
 * @param profile 表格中选中的管理员记录
 * @returns 无返回值，用户取消确认时不做任何提示
 */
async function handleDelete(profile: ProfileRow) {
  try {
    await ElMessageBox.confirm(
      `确定要删除学校管理员「${profile.real_name || profile.email}」吗？`,
      '危险操作',
      { type: 'error', confirmButtonText: '删除' },
    )
    const { error } = await supabase.from('profiles').delete().eq('id', profile.id)
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
            (profile) =>
              !searchKw ||
              profile.real_name.toLowerCase().includes(searchKw.toLowerCase()) ||
              profile.email.toLowerCase().includes(searchKw.toLowerCase()),
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
          <template #default="{ row: profile }">
            {{ profile.created_at ? new Date(profile.created_at).toLocaleString() : '-' }}
          </template>
        </el-table-column>
        <el-table-column label="操作" width="180" fixed="right" align="center">
          <template #default="{ row: profile }">
            <el-button link type="primary" :icon="Edit" @click="openEdit(profile as ProfileRow)">
              编辑
            </el-button>
            <el-button
              link
              type="danger"
              :icon="Delete"
              @click="handleDelete(profile as ProfileRow)"
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
              v-for="school in schoolOptions"
              :key="school.id"
              :value="school.id"
              :label="school.name"
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
