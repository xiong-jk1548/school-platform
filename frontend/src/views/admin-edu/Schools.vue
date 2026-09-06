<script setup lang="ts">
import { ElMessage, ElMessageBox } from 'element-plus'
import type { FormInstance, FormRules } from 'element-plus'
import { ref, reactive, computed, onMounted } from 'vue'
import { supabase } from '@/api/supabase'
import { Plus, Edit, Delete, Check, Close, Search } from '@element-plus/icons-vue'

interface SchoolRow {
  id: string
  name: string
  code: string
  address?: string
  contact_phone?: string
  status: 'active' | 'disabled'
  created_at?: string
}

interface SchoolForm {
  id?: string
  name: string
  code: string
  address: string
  contact_phone: string
  status: 'active' | 'disabled'
}

const loading = ref(false)
const tableData = ref<SchoolRow[]>([])
const searchKw = ref('')

const dialogVisible = ref(false)
const dialogTitle = ref('新增学校')
const formRef = ref<FormInstance>()
const formLoading = ref(false)
const isEdit = ref(false)

const form = reactive<SchoolForm>({
  name: '',
  code: '',
  address: '',
  contact_phone: '',
  status: 'active',
})

const rules = reactive<FormRules<SchoolForm>>({
  name: [{ required: true, message: '请输入学校名称', trigger: 'blur' }],
  code: [{ required: true, message: '请输入学校代码', trigger: 'blur' }],
})

const filteredData = computed(() => {
  const kw = searchKw.value.trim().toLowerCase()
  if (!kw) return tableData.value
  return tableData.value.filter(
    (s) =>
      s.name.toLowerCase().includes(kw) ||
      s.code.toLowerCase().includes(kw),
  )
})

async function loadData() {
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('schools')
      .select('*')
      .order('created_at', { ascending: false })
    if (error) throw error
    tableData.value = (data ?? []) as SchoolRow[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '加载学校列表失败')
  } finally {
    loading.value = false
  }
}

function openAdd() {
  isEdit.value = false
  dialogTitle.value = '新增学校'
  Object.assign(form, {
    name: '',
    code: '',
    address: '',
    contact_phone: '',
    status: 'active' as const,
  })
  dialogVisible.value = true
}

function openEdit(row: SchoolRow) {
  isEdit.value = true
  dialogTitle.value = '编辑学校'
  Object.assign(form, {
    id: row.id,
    name: row.name,
    code: row.code,
    address: row.address ?? '',
    contact_phone: row.contact_phone ?? '',
    status: row.status,
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
        .from('schools')
        .update({
          name: form.name,
          code: form.code,
          address: form.address || null,
          contact_phone: form.contact_phone || null,
          status: form.status,
        })
        .eq('id', form.id)
      if (error) throw error
      ElMessage.success('更新成功')
    } else {
      const { error } = await supabase.from('schools').insert({
        name: form.name,
        code: form.code,
        address: form.address || null,
        contact_phone: form.contact_phone || null,
        status: form.status,
      })
      if (error) throw error
      ElMessage.success('新增成功')
    }
    dialogVisible.value = false
    await loadData()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '保存失败')
  } finally {
    formLoading.value = false
  }
}

async function toggleStatus(row: SchoolRow) {
  const next = row.status === 'active' ? 'disabled' : 'active'
  const label = next === 'active' ? '启用' : '禁用'
  try {
    await ElMessageBox.confirm(`确定要${label}学校「${row.name}」吗？`, '提示', {
      type: 'warning',
    })
    const { error } = await supabase
      .from('schools')
      .update({ status: next })
      .eq('id', row.id)
    if (error) throw error
    ElMessage.success(`${label}成功`)
    await loadData()
  } catch (err: unknown) {
    if (err !== 'cancel') {
      ElMessage.error(err instanceof Error ? err.message : '操作失败')
    }
  }
}

async function handleDelete(row: SchoolRow) {
  try {
    await ElMessageBox.confirm(
      `确定要删除学校「${row.name}」吗？此操作不可恢复。`,
      '危险操作',
      { type: 'error', confirmButtonText: '删除', confirmButtonClass: 'el-button--danger' },
    )
    const { error } = await supabase.from('schools').delete().eq('id', row.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadData()
  } catch (err: unknown) {
    if (err !== 'cancel') {
      ElMessage.error(err instanceof Error ? err.message : '删除失败')
    }
  }
}

onMounted(loadData)
</script>

<template>
  <div class="page">
    <el-card shadow="never">
      <div class="toolbar">
        <div class="toolbar-left">
          <el-input
            v-model="searchKw"
            placeholder="搜索学校名称或代码"
            :prefix-icon="Search"
            clearable
            style="width: 260px"
          />
        </div>
        <el-button type="primary" :icon="Plus" @click="openAdd">新增学校</el-button>
      </div>

      <el-table :data="filteredData" v-loading="loading" stripe>
        <el-table-column prop="name" label="学校名称" min-width="160" />
        <el-table-column prop="code" label="学校代码" width="140" />
        <el-table-column prop="address" label="地址" min-width="180" show-overflow-tooltip />
        <el-table-column prop="contact_phone" label="联系电话" width="140" />
        <el-table-column label="状态" width="100" align="center">
          <template #default="{ row }">
            <el-tag v-if="row.status === 'active'" type="success" effect="light">
              启用
            </el-tag>
            <el-tag v-else type="info" effect="light">禁用</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="created_at" label="创建时间" width="180">
          <template #default="{ row }">
            {{ row.created_at ? new Date(row.created_at).toLocaleString() : '-' }}
          </template>
        </el-table-column>
        <el-table-column label="操作" width="260" fixed="right" align="center">
          <template #default="{ row }">
            <el-button link type="primary" :icon="Edit" @click="openEdit(row as SchoolRow)">
              编辑
            </el-button>
            <el-button
              link
              :type="row.status === 'active' ? 'warning' : 'success'"
              :icon="row.status === 'active' ? Close : Check"
              @click="toggleStatus(row as SchoolRow)"
            >
              {{ row.status === 'active' ? '禁用' : '启用' }}
            </el-button>
            <el-button
              link
              type="danger"
              :icon="Delete"
              @click="handleDelete(row as SchoolRow)"
            >
              删除
            </el-button>
          </template>
        </el-table-column>
      </el-table>

      <div class="footer-hint">共 {{ filteredData.length }} 条记录</div>
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
        <el-form-item label="学校名称" prop="name">
          <el-input v-model="form.name" placeholder="请输入学校全称" />
        </el-form-item>
        <el-form-item label="学校代码" prop="code">
          <el-input v-model="form.code" placeholder="如：SCH001" />
        </el-form-item>
        <el-form-item label="地址">
          <el-input v-model="form.address" placeholder="请输入学校地址" />
        </el-form-item>
        <el-form-item label="联系电话">
          <el-input v-model="form.contact_phone" placeholder="请输入联系电话" />
        </el-form-item>
        <el-form-item label="状态">
          <el-radio-group v-model="form.status">
            <el-radio-button value="active">启用</el-radio-button>
            <el-radio-button value="disabled">禁用</el-radio-button>
          </el-radio-group>
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

.footer-hint {
  margin-top: 12px;
  font-size: 12px;
  color: #909399;
}
</style>
