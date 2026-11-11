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

const loginFormRef = ref<FormInstance>()
const loginSubmitting = ref(false)

/** 登录表单字段；account 兼收手机号与邮箱，具体走哪种由内容形态判断 */
interface LoginCredentials {
  account: string
  password: string
}

const credentials = reactive<LoginCredentials>({
  account: '',
  password: '',
})

const loginFormRules = reactive<FormRules<LoginCredentials>>({
  account: [
    { required: true, message: '请输入手机号或邮箱', trigger: 'blur' },
  ],
  password: [{ required: true, message: '请输入密码', trigger: 'blur' }],
})

/**
 * 提交登录：按账号形态二选一走 Supabase 密码登录，成功后同步用户档案并跳转。
 * @returns Promise<void>，校验不通过或登录失败时提前返回
 *
 * 坑：早期版本这里恒传 { email }，导致用手机号建的账号必然登录失败——
 * gotrue 本身支持 { phone, password }，纯粹是前端漏了分支。
 */
async function submitLogin() {
  const isValid = await loginFormRef.value?.validate().catch(() => false)
  if (!isValid) return
  loginSubmitting.value = true
  try {
    // 输入为 11 位纯数字手机号时走 phone 登录，否则按邮箱处理
    const accountInput = credentials.account.trim()
    const isPhoneAccount = /^\d{11}$/.test(accountInput)
    const { error } = await supabase.auth.signInWithPassword(
      isPhoneAccount
        ? { phone: accountInput, password: credentials.password }
        : { email: accountInput, password: credentials.password },
    )
    if (error) throw error
    await userStore.syncFromSession()
    ElMessage.success('登录成功')
    const redirect = (route.query.redirect as string) || '/'
    router.push(redirect)
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '登录失败')
  } finally {
    loginSubmitting.value = false
  }
}

</script>

<template>
  <div class="platform-login-page">
    <div class="platform-login-card">
      <h1 class="platform-login-title">智慧校园管理平台</h1>
      <p class="platform-login-subtitle">面向教师 · 班级数字化管理</p>

      <el-form
        ref="loginFormRef"
        :model="credentials"
        :rules="loginFormRules"
        label-position="top"
        size="large"
        @submit.prevent="submitLogin"
      >
        <el-form-item label="手机号 / 邮箱" prop="account">
          <el-input
            v-model="credentials.account"
            type="text"
            placeholder="请输入手机号或邮箱"
            :prefix-icon="User"
            autocomplete="username"
          />
        </el-form-item>
        <el-form-item label="密码" prop="password">
          <el-input
            v-model="credentials.password"
            type="password"
            placeholder="请输入密码"
            :prefix-icon="Lock"
            show-password
            autocomplete="current-password"
            @keyup.enter="submitLogin"
          />
        </el-form-item>
        <el-button
          type="primary"
          :loading="loginSubmitting"
          class="platform-login-submit"
          @click="submitLogin"
        >
          登 录
        </el-button>
      </el-form>
    </div>
  </div>
</template>

<style scoped>
.platform-login-page {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #1e6fd9 0%, #4a90e2 100%);
  padding: 24px;
}

.platform-login-card {
  width: 100%;
  max-width: 440px;
  padding: 40px 36px 32px;
  background: #fff;
  border-radius: 12px;
  box-shadow: 0 20px 40px rgba(30, 111, 217, 0.25);
}

.platform-login-title {
  margin: 0;
  font-size: 22px;
  font-weight: 600;
  color: #1e6fd9;
  text-align: center;
}

.platform-login-subtitle {
  margin: 8px 0 28px;
  font-size: 14px;
  color: #8892a4;
  text-align: center;
}

.platform-login-submit {
  width: 100%;
  margin-top: 12px;
  background: #1e6fd9;
  border-color: #1e6fd9;
}

.platform-login-submit:hover {
  background: #185bb5;
  border-color: #185bb5;
}
</style>