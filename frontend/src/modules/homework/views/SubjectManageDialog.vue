<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import type { FormInstance, FormRules } from 'element-plus'
import { Plus, Edit, Delete } from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'

const props = defineProps<{ visible: boolean }>()
const emit = defineEmits<{ (e: 'update:visible', v: boolean): void; (e: 'refresh'): void }>()

const userStore = useUserStore()

const canEdit = computed(() => userStore.role !== 'sys_admin')

interface SubjectRow {
  id: string
  subject_name: string
  name?: string
  sort_order: number
}

const subjects = ref<SubjectRow[]>([])
const loading = ref(false)

const editDialogVisible = ref(false)
const isEdit = ref(false)
const formRef = ref<FormInstance>()
const submitting = ref(false)
const form = ref<SubjectRow>({ id: '', subject_name: '', sort_order: 0 })

const formRules: FormRules = {
  subject_name: [{ required: true, message: '请输入科目名称', trigger: 'blur' }],
  sort_order: [{ required: true, message: '请输入排序号', trigger: 'blur' }],
}

async function loadSubjects() {
  if (!userStore.schoolId) return
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('homework_subjects')
      .select('id, subject_name, sort_order')
      .eq('school_id', userStore.schoolId)
      .order('sort_order', { ascending: true })
    if (error) throw error
    subjects.value = (data ?? []) as SubjectRow[]
  } catch (err: any) {
    ElMessage.error(err.message || '加载科目列表失败')
  } finally {
    loading.value = false
  }
}

function openAdd() {
  isEdit.value = false
  form.value = { id: '', subject_name: '', sort_order: subjects.value.length + 1 }
  editDialogVisible.value = true
}

function openEdit(row: SubjectRow) {
  isEdit.value = true
  form.value = { ...row }
  editDialogVisible.value = true
}

async function handleSubmit() {
  try {
    await formRef.value?.validate()
  } catch {
    return
  }
  if (!userStore.schoolId) return
  submitting.value = true
  try {
    if (isEdit.value) {
      const { error } = await supabase
        .from('homework_subjects')
        .update({
          subject_name: form.value.subject_name,
          sort_order: form.value.sort_order,
        })
        .eq('id', form.value.id)
      if (error) throw error
      ElMessage.success('更新成功')
    } else {
      const { error } = await supabase.from('homework_subjects').insert({
        subject_name: form.value.subject_name,
        school_id: userStore.schoolId,
        sort_order: form.value.sort_order,
      })
      if (error) throw error
      ElMessage.success('新增成功')
    }
    editDialogVisible.value = false
    await loadSubjects()
    emit('refresh')
  } catch (err: any) {
    ElMessage.error(err.message || '保存失败')
  } finally {
    submitting.value = false
  }
}

async function handleDelete(row: SubjectRow) {
  try {
    await ElMessageBox.confirm(`确定删除科目「${row.subject_name}」吗？`, '提示', {
      type: 'warning',
    })
  } catch {
    return
  }
  try {
    const { error } = await supabase.from('homework_subjects').delete().eq('id', row.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadSubjects()
    emit('refresh')
  } catch (err: any) {
    ElMessage.error(err.message || '删除失败')
  }
}

const editDialogTitle = computed(() => (isEdit.value ? '编辑科目' : '新增科目'))

watch(
  () => props.visible,
  (v) => {
    if (v) loadSubjects()
  },
)
</script>

<template>
  <el-dialog
    :model-value="visible"
    title="科目管理"
    width="600px"
    @update:model-value="(v: boolean) => emit('update:visible', v)"
    destroy-on-close
  >
    <div class="dialog-actions">
      <el-button
        v-if="canEdit"
        type="primary"
        :icon="Plus"
        @click="openAdd"
      >
        新增科目
      </el-button>
      <el-tag v-else type="info" effect="plain">只读模式（教师）</el-tag>
    </div>

    <el-table :data="subjects" v-loading="loading" border stripe style="width: 100%">
      <el-table-column prop="subject_name" label="科目名" min-width="160" />
      <el-table-column prop="sort_order" label="排序" width="100" align="center" />
      <el-table-column v-if="canEdit" label="操作" width="180" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" :icon="Edit" @click="openEdit(row as SubjectRow)">编辑</el-button>
          <el-button link type="danger" :icon="Delete" @click="handleDelete(row as SubjectRow)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <template #footer>
      <el-button @click="emit('update:visible', false)">关闭</el-button>
    </template>
  </el-dialog>

  <el-dialog
    v-model="editDialogVisible"
    :title="editDialogTitle"
    width="420px"
    destroy-on-close
  >
    <el-form ref="formRef" :model="form" :rules="formRules" label-width="80px">
      <el-form-item label="科目名" prop="subject_name">
        <el-input v-model="form.subject_name" placeholder="例如：语文" />
      </el-form-item>
      <el-form-item label="排序号" prop="sort_order">
        <el-input-number v-model="form.sort_order" :min="1" :step="1" style="width: 100%" />
      </el-form-item>
    </el-form>
    <template #footer>
      <el-button @click="editDialogVisible = false">取消</el-button>
      <el-button type="primary" :loading="submitting" @click="handleSubmit">确定</el-button>
    </template>
  </el-dialog>
</template>

<style scoped>
.dialog-actions {
  margin-bottom: 12px;
}
</style>
