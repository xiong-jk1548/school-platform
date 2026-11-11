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

// 教师现在也由 RLS（hw_subject teacher write）授权管理本校科目
const canEdit = computed(() => !!userStore.schoolId)

// 中小学常见科目预设（选择或直接输入自定义科目）
const PRESET_SUBJECTS = [
  '语文', '数学', '英语', '物理', '化学', '生物',
  '道德与法治', '历史', '地理', '科学',
  '音乐', '美术', '体育', '信息技术', '劳动', '书法', '心理健康',
]

// 下拉选项：预设科目 + 已添加的自定义科目；已存在的预设标记为禁用
const subjectOptions = computed(() => {
  const existingSubjectNames = new Set(subjectList.value.map((subjectRow) => subjectRow.subject_name))
  const presetOptions = PRESET_SUBJECTS.map((subjectName) => ({
    value: subjectName,
    label: existingSubjectNames.has(subjectName) ? `${subjectName}（已添加）` : subjectName,
    disabled: existingSubjectNames.has(subjectName) && subjectName !== form.value.subject_name,
  }))
  const customSubjectOptions = subjectList.value
    .filter((subjectRow) => !PRESET_SUBJECTS.includes(subjectRow.subject_name))
    .map((subjectRow) => ({ value: subjectRow.subject_name, label: `${subjectRow.subject_name}（已添加）`, disabled: true }))
  return [...presetOptions, ...customSubjectOptions]
})

interface SubjectRow {
  id: string
  subject_name: string
  name?: string
  sort_order: number
}

const subjectList = ref<SubjectRow[]>([])
const subjectsLoading = ref(false)

const editDialogVisible = ref(false)
const isEdit = ref(false)
const formRef = ref<FormInstance>()
const submitting = ref(false)
const form = ref<SubjectRow>({ id: '', subject_name: '', sort_order: 0 })

const formRules: FormRules = {
  subject_name: [{ required: true, message: '请选择或输入科目名称', trigger: 'change' }],
  sort_order: [{ required: true, message: '请输入排序号', trigger: 'blur' }],
}

/**
 * 按当前登录账号的学校加载已配置的作业科目。
 * @returns 无返回值（副作用：写入 subjectList，并维护 subjectsLoading 状态）
 */
async function loadSubjects() {
  if (!userStore.schoolId) return
  subjectsLoading.value = true
  try {
    const { data: subjectRows, error } = await supabase
      .from('homework_subjects')
      .select('id, subject_name, sort_order')
      .eq('school_id', userStore.schoolId)
      .order('sort_order', { ascending: true })
    if (error) throw error
    subjectList.value = (subjectRows ?? []) as SubjectRow[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载科目列表失败')
  } finally {
    subjectsLoading.value = false
  }
}

/** 打开新增科目弹窗，排序号默认排在现有科目之后 */
function openAdd() {
  isEdit.value = false
  form.value = { id: '', subject_name: '', sort_order: subjectList.value.length + 1 }
  editDialogVisible.value = true
}

/**
 * 打开编辑弹窗，并把选中科目回填到表单。
 * @param subjectRow 待编辑的科目行
 * @returns 无返回值
 */
function openEdit(subjectRow: SubjectRow) {
  isEdit.value = true
  form.value = { ...subjectRow }
  editDialogVisible.value = true
}

/**
 * 提交科目表单：校验必填与重名后，按新增/编辑分别写入 homework_subjects。
 * @returns 无返回值；成功后关闭弹窗、刷新列表并通知父组件
 */
async function handleSubmit() {
  try {
    await formRef.value?.validate()
  } catch {
    // 表单校验未通过，ElForm 已提示错误，这里直接中断提交
    return
  }
  if (!userStore.schoolId) return
  const subjectName = form.value.subject_name.trim()
  if (!subjectName) return
  const duplicatedSubject = subjectList.value.some((subjectRow) => subjectRow.subject_name === subjectName && subjectRow.id !== form.value.id)
  if (duplicatedSubject) {
    ElMessage.warning(`科目「${subjectName}」已存在，无需重复添加`)
    return
  }
  form.value.subject_name = subjectName
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
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存失败')
  } finally {
    submitting.value = false
  }
}

/**
 * 删除指定科目（删除前二次确认）。
 * @param subjectRow 待删除的科目行
 * @returns 无返回值；成功后刷新列表并通知父组件
 */
async function handleDelete(subjectRow: SubjectRow) {
  try {
    await ElMessageBox.confirm(`确定删除科目「${subjectRow.subject_name}」吗？`, '提示', {
      type: 'warning',
    })
  } catch {
    // 用户在确认框中取消删除，直接结束
    return
  }
  try {
    const { error } = await supabase.from('homework_subjects').delete().eq('id', subjectRow.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadSubjects()
    emit('refresh')
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '删除失败')
  }
}

const editDialogTitle = computed(() => (isEdit.value ? '编辑科目' : '新增科目'))

watch(
  () => props.visible,
  (dialogVisible) => {
    if (dialogVisible) loadSubjects()
  },
)
</script>

<template>
  <el-dialog
    :model-value="visible"
    title="科目管理"
    width="600px"
    @update:model-value="(dialogVisibleValue: boolean) => emit('update:visible', dialogVisibleValue)"
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
    </div>

    <el-alert
      v-if="subjectList.length === 0 && canEdit"
      type="info"
      :closable="false"
      show-icon
      title="还没有科目，点击「新增科目」从常用科目中选择，或直接输入自定义科目。设置后全校共享，之后默认使用这些科目。"
      style="margin-bottom: 12px"
    />

    <el-table :data="subjectList" v-loading="subjectsLoading" border stripe style="width: 100%">
      <el-table-column prop="subject_name" label="科目名" min-width="160" />
      <el-table-column prop="sort_order" label="排序" width="100" align="center" />
      <el-table-column v-if="canEdit" label="操作" width="180" fixed="right">
        <template #default="{ row: subjectRow }">
          <el-button link type="primary" :icon="Edit" @click="openEdit(subjectRow as SubjectRow)">编辑</el-button>
          <el-button link type="danger" :icon="Delete" @click="handleDelete(subjectRow as SubjectRow)">删除</el-button>
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
        <el-select
          v-model="form.subject_name"
          filterable
          allow-create
          default-first-option
          placeholder="选择常用科目，或输入自定义科目"
          style="width: 100%"
        >
          <el-option
            v-for="subjectOption in subjectOptions"
            :key="subjectOption.value"
            :value="subjectOption.value"
            :label="subjectOption.label"
            :disabled="subjectOption.disabled"
          />
        </el-select>
        <div class="form-tip">可直接点击选择预设科目；列表中没有的科目请直接输入名称</div>
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
.form-tip {
  font-size: 12px;
  color: var(--el-text-color-secondary);
  line-height: 1.4;
  margin-top: 4px;
}
</style>
