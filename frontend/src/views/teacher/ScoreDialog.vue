<script setup lang="ts">
import { ref } from 'vue'
import { ElMessage } from 'element-plus'
import { supabase } from '@/api/supabase'

interface StudentRow {
  id: string
  student_name: string
  name?: string
}

const REMARK_OPTIONS = [
  { label: '获奖', value: '获奖' },
  { label: '表扬', value: '表扬' },
  { label: '课堂表现好', value: '课堂表现好' },
  { label: '作业优秀', value: '作业优秀' },
  { label: '积极发言', value: '积极发言' },
  { label: '迟到', value: '迟到' },
  { label: '违反纪律', value: '违反纪律' },
  { label: '作业未交', value: '作业未交' },
  { label: '其他', value: '__other__' },
]

const emit = defineEmits<{ (e: 'submitted'): void }>()

const dialogVisible = ref(false)
const dialogTitle = ref('')
const currentStudent = ref<StudentRow | null>(null)
const scoreValue = ref(1)
const remarkSelected = ref('')
const remarkCustom = ref('')
const submitting = ref(false)

const showCustomRemark = ref(false)

// 暴露给父组件（学生管理页）通过 ref 调用的开窗方法
defineExpose({
  /**
   * 打开积分变动弹窗
   * @param student 被操作的学生
   * @param type 操作类型：add 加分 / deduct 扣分（决定标题文案与默认分值）
   */
  open(student: StudentRow, type: 'add' | 'deduct') {
    currentStudent.value = student
    dialogTitle.value = type === 'add'
      ? `给 ${student.student_name || student.name} 加分`
      : `给 ${student.student_name || student.name} 扣分`
    scoreValue.value = type === 'add' ? 1 : -1
    remarkSelected.value = ''
    remarkCustom.value = ''
    showCustomRemark.value = false
    dialogVisible.value = true
  },
})

/**
 * 计算最终生效的积分变动原因：下拉选择「其他」时取自定义输入并去除首尾空格
 * @returns 积分变动原因文本（可能为空字符串）
 */
function effectiveRemark(): string {
  if (remarkSelected.value === '__other__') return remarkCustom.value.trim()
  return remarkSelected.value
}

/**
 * 提交本次积分变动
 * 调用数据库函数 fn_change_student_score 完成加分/扣分，成功后关闭弹窗并通知父组件刷新列表
 * @returns 无返回值（副作用：写入 score_log 流水、关闭弹窗、emit submitted 事件）
 */
async function handleSubmitScore() {
  if (!currentStudent.value) return
  const remark = effectiveRemark()
  if (!remark) {
    ElMessage.warning('请选择或填写积分变动原因')
    return
  }
  submitting.value = true
  try {
    const { error } = await supabase.rpc('fn_change_student_score', {
      p_student_id: currentStudent.value.id,
      p_score_change: scoreValue.value,
      p_remark: remark,
    })
    if (error) throw error
    ElMessage.success('积分操作成功')
    dialogVisible.value = false
    emit('submitted')
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '积分操作失败')
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <el-dialog v-model="dialogVisible" :title="dialogTitle" width="460px" destroy-on-close>
    <el-form label-width="80px">
      <el-form-item label="分值">
        <el-input-number
          v-model="scoreValue"
          :min="-100"
          :max="100"
          :step="1"
          style="width: 100%"
        />
      </el-form-item>
      <el-form-item label="原因" required>
        <el-select
          v-model="remarkSelected"
          placeholder="请选择积分变动原因"
          style="width: 100%"
          @change="(selectedRemark: string) => { showCustomRemark = selectedRemark === '__other__' }"
        >
          <el-option
            v-for="remarkOption in REMARK_OPTIONS"
            :key="remarkOption.value"
            :label="remarkOption.label"
            :value="remarkOption.value"
          />
        </el-select>
      </el-form-item>
      <el-form-item v-if="showCustomRemark" label="说明" required>
        <el-input
          v-model="remarkCustom"
          placeholder="请输入具体原因"
          maxlength="100"
        />
      </el-form-item>
    </el-form>
    <template #footer>
      <el-button @click="dialogVisible = false">取消</el-button>
      <el-button type="primary" :loading="submitting" @click="handleSubmitScore">确定</el-button>
    </template>
  </el-dialog>
</template>
