<script setup lang="ts">
import { ElMessage } from 'element-plus'
import type { FormInstance, FormRules } from 'element-plus'
import { ref, reactive } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useUserStore } from '@/stores/user'
import { supabase } from '@/api/supabase'
import { User, Lock } from '@element-plus/icons-vue'

const router = useRouter()
const route = useRoute()
const userStore = useUserStore()

const formRef = ref<FormInstance>()
const isSubmitting = ref(false)

interface LoginForm {
  email: string
  password: string
}

const form = reactive<LoginForm>({
  email: '',
  password: '',
})

const rules = reactive<FormRules<LoginForm>>({
  email: [
    { required: true, message: '请输入手机号', trigger: 'blur' },
  ],
  password: [{ required: true, message: '请输入密码', trigger: 'blur' }],
})

async function handleSubmit() {
  const valid = await formRef.value?.validate().catch(() => false)
  if (!valid) return
  isSubmitting.value = true
  try {
    const { error } = await supabase.auth.signInWithPassword({
      email: form.email,
      password: form.password,
    })
    if (error) throw error
    await userStore.syncFromSession()
    ElMessage.success('登录成功')
    const redirect = (route.query.redirect as string) || '/'
    router.push(redirect)
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '登录失败')
  } finally {
    isSubmitting.value = false
  }
}

const testAccounts = [
  { role: '教育局管理员', phone: '13800000001', password: '123456' },
  { role: '学校管理员', phone: '13800000002', password: '123456' },
  { role: '教师', phone: '13800000003', password: '123456' },
]
</script>

<template>
  <div class="login-container">
    <div class="login-card">
      <h1 class="login-title">校园信息化服务平台</h1>
      <p class="login-subtitle">面向教师 · 班级数字化管理</p>

      <el-form
        ref="formRef"
        :model="form"
        :rules="rules"
        label-position="top"
        size="large"
        @submit.prevent="handleSubmit"
      >
        <el-form-item label="手机号" prop="email">
          <el-input
            v-model="form.email"
            type="text"
            placeholder="请输入手机号"
            :prefix-icon="User"
            autocomplete="username"
          />
        </el-form-item>
        <el-form-item label="密码" prop="password">
          <el-input
            v-model="form.password"
            type="password"
            placeholder="请输入密码"
            :prefix-icon="Lock"
            show-password
            autocomplete="current-password"
            @keyup.enter="handleSubmit"
          />
        </el-form-item>
        <el-button
          type="primary"
          :loading="isSubmitting"
          class="login-btn"
          @click="handleSubmit"
        >
          登 录
        </el-button>
      </el-form>

      <div class="test-hint">
        <div class="test-hint-title">测试账号</div>
        <div
          v-for="acc in testAccounts"
          :key="acc.phone"
          class="test-hint-row"
        >
          <span class="role-tag">{{ acc.role }}</span>
          <span class="cred">
            {{ acc.phone }} / {{ acc.password }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.login-container {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #1e6fd9 0%, #4a90e2 100%);
  padding: 24px;
}

.login-card {
  width: 100%;
  max-width: 440px;
  padding: 40px 36px 32px;
  background: #fff;
  border-radius: 12px;
  box-shadow: 0 20px 40px rgba(30, 111, 217, 0.25);
}

.login-title {
  margin: 0;
  font-size: 22px;
  font-weight: 600;
  color: #1e6fd9;
  text-align: center;
}

.login-subtitle {
  margin: 8px 0 28px;
  font-size: 14px;
  color: #8892a4;
  text-align: center;
}

.login-btn {
  width: 100%;
  margin-top: 12px;
  background: #1e6fd9;
  border-color: #1e6fd9;
}

.login-btn:hover {
  background: #185bb5;
  border-color: #185bb5;
}

.test-hint {
  margin-top: 24px;
  padding-top: 16px;
  border-top: 1px dashed #dcdfe6;
  font-size: 12px;
  color: #909399;
}

.test-hint-title {
  font-weight: 600;
  margin-bottom: 8px;
  color: #606266;
}

.test-hint-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 4px;
}

.role-tag {
  display: inline-block;
  min-width: 72px;
  padding: 1px 8px;
  font-size: 11px;
  color: #1e6fd9;
  background: #eaf3ff;
  border-radius: 10px;
  text-align: center;
}

.cred {
  font-family: 'Courier New', monospace;
  color: #606266;
}
</style>
