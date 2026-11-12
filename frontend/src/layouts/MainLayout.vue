<script setup lang="ts">
import { computed, ref, watch, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useUserStore } from '@/stores/user'
import { navMenus, type TeacherView } from '@/router/menus'
import { getSwitchableRoles, switchRole } from '@/utils/role-switch'
import { supabase } from '@/api/supabase'
import {
  School,
  Reading,
  ArrowDown,
  Lock,
  SwitchButton,
  Refresh,
  User,
} from '@element-plus/icons-vue'

const userStore = useUserStore()
const route = useRoute()
const router = useRouter()

const navSidebarWidth = '220px'

/** 响应式布局标记：视口宽度小于 768px 时侧边导航改由抽屉承载 */
const isMobileViewport = ref(false)
const mobileNavVisible = ref(false)

/**
 * 按当前视口宽度刷新移动端标记（<768px 判定为移动端，侧边栏改抽屉）。
 * @returns 无
 */
function syncMobileViewport() {
  isMobileViewport.value = window.innerWidth < 768
}
onMounted(() => {
  syncMobileViewport()
  window.addEventListener('resize', syncMobileViewport)
})
onUnmounted(() => window.removeEventListener('resize', syncMobileViewport))

const TEACHER_VIEW_STORAGE_KEY = 'MOCK_TEACHER_VIEW'
const teacherViewMode = ref<TeacherView>(localStorage.getItem(TEACHER_VIEW_STORAGE_KEY) as TeacherView || 'frontend')

/** 教师视图模式变化即落盘，刷新后仍停留在上次选择的前端/后台 */
watch(teacherViewMode, (nextViewMode) => {
  localStorage.setItem(TEACHER_VIEW_STORAGE_KEY, nextViewMode)
})

/** 本学校全部班级记录，作为顶栏班级下拉的候选项 */
const schoolClassOptions = ref<{ id: string; class_name: string; grade?: string; homeroom_teacher_id?: string | null }[]>([])

/**
 * 拉取本学校全部班级，供顶栏班级下拉使用。
 * @returns Promise<void>，未绑定学校时直接返回
 *
 * 坑：schoolId 为 null 时必须提前 return —— 拿空值去过滤既筛不出数据，
 * 下拉也会变成空白（"年级下拉空"那次就是这么漏的兜底）。
 */
async function fetchSchoolClasses() {
  if (!userStore.schoolId) return
  try {
    const { data: classRecords } = await supabase
      .from('classes')
      .select('id, class_name, grade, homeroom_teacher_id')
      .eq('school_id', userStore.schoolId)
    schoolClassOptions.value = (classRecords ?? []) as any
  } catch { /* ignore */ }
}

watch(() => userStore.role, fetchSchoolClasses)
watch(() => userStore.schoolId, fetchSchoolClasses)
onMounted(fetchSchoolClasses)

/**
 * 班级列表就绪后兜底选中班级：教师身份下若从没选过班，默认取第一个；
 * 已选但该班已不在列表里（例如管理员切到教师身份后），同样重置为第一个。
 * @param classOptions 最新的班级列表
 * @returns 无
 */
/**
 * 兜底班级：优先取教师档案里绑定的班级，取不到才退回列表第一条。
 * ⚠️ 必须与后端 RLS 的 class_id 基准（JWT 里的 user_metadata.class_id）一致：
 * 随手取 classOptions[0] 会选中同校的另一个班，导致按班级隔离的数据（物品借阅、
 * 作业登记等）读取为空、写入被 RLS 拒绝。
 * @param classOptions 本学校班级列表
 * @returns 兜底选中的班级记录；列表为空时返回 undefined
 */
function resolveFallbackClass(
  classOptions: { id: string; class_name: string; grade?: string; homeroom_teacher_id?: string | null }[],
) {
  const boundClass = userStore.boundClassId
    ? classOptions.find((classItem) => classItem.id === userStore.boundClassId)
    : undefined
  return boundClass ?? classOptions[0]
}

/**
 * 班级列表就绪后兜底选中班级：教师身份下若从没选过班，默认取自己绑定的班；
 * 已选但该班已不在列表里（例如管理员切到教师身份后），同样按上面的规则重置。
 * @param classOptions 最新的班级列表
 * @returns 无
 */
watch(schoolClassOptions, (classOptions) => {
  if (!classOptions || classOptions.length === 0) return
  if (userStore.role !== 'teacher') return
  if (userStore.selectedClassId) {
    // 已选但 selectedClassId 不在下拉里（例如管理员切到 teacher 后），就重置
    if (!classOptions.find((classItem) => classItem.id === userStore.selectedClassId)) {
      const fallbackClass = resolveFallbackClass(classOptions)
      if (fallbackClass) userStore.setSelectedClass(fallbackClass.id, fallbackClass.class_name)
    }
    return
  }
  const fallbackClass = resolveFallbackClass(classOptions)
  if (fallbackClass) userStore.setSelectedClass(fallbackClass.id, fallbackClass.class_name)
})

/**
 * 顶栏班级下拉变更时把选中班级写进 store。
 * @param selectedClassId 选中的 classes.id
 * @returns Promise<void>
 */
async function handleClassSelect(selectedClassId: string) {
  const matchedClass = schoolClassOptions.value.find((classItem) => classItem.id === selectedClassId)
  if (!matchedClass) return
  userStore.setSelectedClass(matchedClass.id, matchedClass.class_name)
  // 如果没有选班，自动切回前端
  if (!userStore.selectedClassId) {
    teacherViewMode.value = 'frontend'
  }
}

/**
 * 侧边栏最终可见的菜单：按"角色 → 教师视图模式 → 是否已选班级"三级过滤。
 * 后台类菜单只要求已选班级，是否真的能读写由后端 RLS 按 class_id / school_id 决定。
 * @returns 当前角色与视图模式下应当展示的菜单项数组
 */
const visibleMenus = computed(() => {
  return navMenus.filter((menu) => {
    if (!userStore.role || !menu.roles.includes(userStore.role)) return false
    if (userStore.role === 'teacher') {
      if (menu.teacherView && !menu.teacherView.includes(teacherViewMode.value)) return false
      // 后端菜单：只要当前已选了一个班(active teacher 就行；
      // 真正能不能读写，由后端 RLS 按 class_id / school_id 限制)
      if (teacherViewMode.value === 'backend' && menu.teacherView?.includes('backend')) {
        if (!userStore.selectedClassId) return false
      }
    }
    return true
  })
})

const roleSwitchOptions = computed(() => getSwitchableRoles())

const activeRoleLabel = computed(() => {
  const roleDisplayNames = { sys_admin: '教育局管理员', school_admin: '学校管理员', teacher: '教师' }
  return roleDisplayNames[userStore.role as keyof typeof roleDisplayNames] ?? ''
})

const isTeacherRole = computed(() => userStore.role === 'teacher')
const teacherViewLabel = computed(() => (teacherViewMode.value === 'frontend' ? '班级前端' : '班级后台'))

/**
 * 在前端/后台两种教师视图之间切换，并跳到该视图的第一个菜单。
 * @returns 无
 */
function switchTeacherView() {
  teacherViewMode.value = teacherViewMode.value === 'frontend' ? 'backend' : 'frontend'
  // 切换后跳转到对应视图的第一个菜单
  const firstMenu = visibleMenus.value[0]
  if (firstMenu && route.path !== firstMenu.path) {
    router.push(firstMenu.path)
  }
}

/**
 * 二次确认后退出登录并回到登录页。
 * @returns Promise<void>，用户在确认框点"取消"时静默返回
 */
async function handleLogout() {
  try {
    await ElMessageBox.confirm('确定要退出登录吗？', '提示', {
      confirmButtonText: '退出',
      cancelButtonText: '取消',
      type: 'warning',
    })
    await userStore.logout()
    router.push('/login')
  } catch {
    /* 用户取消 */
  }
}

/**
 * 用户下拉菜单的命令分发。
 * @param command 下拉项绑定的命令名：'logout' 退出登录 / 'change-password' 打开改密弹窗
 * @returns 无
 */
function handleAccountCommand(command: string) {
  if (command === 'logout') {
    handleLogout()
  } else if (command === 'change-password') {
    passwordDialogVisible.value = true
  } else if (command === 'edit-profile') {
    openProfileDialog()
  }
}

// ============ 修改密码 ============
const passwordDialogVisible = ref(false)
const passwordSubmitting = ref(false)
const passwordFormRef = ref()
const passwordForm = ref({ oldPassword: '', newPassword: '', confirmPassword: '' })

/** 改密表单校验规则：新密码至少 6 位；确认密码需与 newPassword 一致（跨字段校验） */
const passwordRules = {
  oldPassword: [{ required: true, message: '请输入当前密码', trigger: 'blur' }],
  newPassword: [
    { required: true, message: '请输入新密码', trigger: 'blur' },
    { min: 6, message: '新密码至少 6 位', trigger: 'blur' },
  ],
  confirmPassword: [
    { required: true, message: '请再次输入新密码', trigger: 'blur' },
    {
      validator: (_rule: any, value: string, callback: any) => {
        if (value !== passwordForm.value.newPassword) callback(new Error('两次输入的密码不一致'))
        else callback()
      },
      trigger: 'blur',
    },
  ],
}

/**
 * 提交修改密码：先拿当前账号+原密码重新登录一次来验旧密码，验过再调 updateUser。
 * @returns Promise<void>，表单校验失败或旧密码错误时提前返回
 *
 * 注意：这里必须显式抛 Error 才能让下面的 catch 统一提示，
 * 所以第二个 try 内部不用区分 Supabase 的 error 对象形态。
 */
async function submitPasswordChange() {
  try {
    await passwordFormRef.value?.validate()
  } catch {
    return
  }
  passwordSubmitting.value = true
  try {
    // 先验证当前密码是否正确（用当前账号重新登录一次）
    const accountIdentifier = userStore.email || userStore.phone || ''
    if (!accountIdentifier) throw new Error('无法确定当前账号，请重新登录')
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: accountIdentifier.includes('@') ? accountIdentifier : undefined as any,
      phone: accountIdentifier.includes('@') ? undefined as any : accountIdentifier,
      password: passwordForm.value.oldPassword,
    })
    if (signInError) throw new Error('当前密码不正确')

    // 修改密码
    const { error } = await supabase.auth.updateUser({
      password: passwordForm.value.newPassword,
    })
    if (error) throw error

    ElMessage.success('密码修改成功，下次登录请使用新密码')
    passwordDialogVisible.value = false
    passwordForm.value = { oldPassword: '', newPassword: '', confirmPassword: '' }
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '密码修改失败')
  } finally {
    passwordSubmitting.value = false
  }
}

// ============ 修改个人信息 ============
const profileDialogVisible = ref(false)
const profileSubmitting = ref(false)
const profileForm = ref({ realName: '', phone: '' })

/** 打开个人信息对话框：用当前登录态预填姓名与手机号 */
function openProfileDialog() {
  profileForm.value.realName = userStore.name ?? ''
  profileForm.value.phone = userStore.phone ?? ''
  profileDialogVisible.value = true
}

/**
 * 保存姓名/手机号：走 update_own_profile RPC（服务端校验归属与手机号唯一性），
 * 档案变更经 15 号触发器自动同步到登录元数据。界面显示立即更新，
 * JWT 元数据在重新登录后完全刷新。
 */
async function submitProfileChange() {
  const realName = profileForm.value.realName.trim()
  if (!realName) {
    ElMessage.warning('姓名不能为空')
    return
  }
  profileSubmitting.value = true
  try {
    const inputPhone = profileForm.value.phone.trim()
    const { data, error } = await supabase.rpc('update_own_profile', {
      p_real_name: realName,
      p_phone: inputPhone || null,
    })
    if (error) throw error
    userStore.name = realName
    const finalPhone = (data as any)?.phone as string | null
    if (finalPhone) userStore.phone = finalPhone
    ElMessage.success(finalPhone && inputPhone && finalPhone !== inputPhone
      ? `已保存。手机号与他人重复，实际生效：${finalPhone}`
      : '个人信息已保存')
    profileDialogVisible.value = false
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存失败')
  } finally {
    profileSubmitting.value = false
  }
}

/**
 * 切换身份入口（下拉选中后由 role-switch 落盘并整页重载）。
 * @param {'sys_admin' | 'school_admin' | 'teacher'} role 目标角色
 * @returns 无
 */
function handleRoleSwitch(role: 'sys_admin' | 'school_admin' | 'teacher') {
  switchRole(role)
}
</script>

<template>
  <el-container class="platform-shell">
    <!-- 桌面端侧边栏 -->
    <el-aside v-if="!isMobileViewport" :width="navSidebarWidth" class="nav-sidebar">
      <div class="brand-banner">
        <span class="brand-emblem">🎓</span>
        <span class="brand-name">智慧校园</span>
      </div>
      <el-menu
        :default-active="route.path"
        :router="true"
        background-color="#001529"
        text-color="#c8d6e5"
        active-text-color="#1E6FD9"
        class="role-nav-menu"
      >
        <template v-for="menu in visibleMenus" :key="menu.path">
          <el-menu-item :index="menu.path">
            <el-icon v-if="menu.icon"><component :is="menu.icon" /></el-icon>
            <span>{{ menu.title }}</span>
          </el-menu-item>
        </template>
      </el-menu>
    </el-aside>

    <!-- 移动端抽屉 -->
    <el-drawer
      v-if="isMobileViewport"
      v-model="mobileNavVisible"
      direction="ltr"
      :size="260"
      :show-close="false"
      :with-header="false"
      class="mobile-nav-drawer"
    >
      <div class="nav-sidebar nav-sidebar-drawer">
        <div class="brand-banner">
          <span class="brand-emblem">🎓</span>
          <span class="brand-name">智慧校园</span>
        </div>
        <el-menu
          :default-active="route.path"
          :router="true"
          background-color="#001529"
          text-color="#c8d6e5"
          active-text-color="#1E6FD9"
          class="role-nav-menu"
          @select="mobileNavVisible = false"
        >
          <template v-for="menu in visibleMenus" :key="menu.path">
            <el-menu-item :index="menu.path">
              <el-icon v-if="menu.icon"><component :is="menu.icon" /></el-icon>
              <span>{{ menu.title }}</span>
            </el-menu-item>
          </template>
        </el-menu>
      </div>
    </el-drawer>

    <el-container>
      <el-header class="top-bar">
        <div class="top-bar-left">
          <el-icon v-if="isMobileViewport" class="mobile-nav-toggle" @click="mobileNavVisible = true">
            <svg viewBox="0 0 1024 1024" width="20" height="20"><path fill="currentColor" d="M128 192h768v64H128zm0 320h768v64H128zm0 320h768v64H128z"/></svg>
          </el-icon>
          <el-breadcrumb separator="/">
            <el-breadcrumb-item :to="{ path: '/' }">
              {{ route.meta.title ?? '首页' }}
            </el-breadcrumb-item>
          </el-breadcrumb>
          <div class="school-identity" v-if="userStore.role === 'school_admin'">
            <el-icon><School /></el-icon>
            <!-- 兜底：学校名 → school_id → 未关联学校（曾把 school_id 当校名显示出一串 UUID） -->
            <span>{{ userStore.schoolName ?? userStore.schoolId ?? '未关联学校' }}</span>
          </div>
          <!-- 教师：班级下拉选择器 -->
          <div class="class-picker" v-if="userStore.role === 'teacher'">
            <el-icon style="color:#2B5CE6"><Reading /></el-icon>
            <el-select
              :model-value="userStore.selectedClassId"
              placeholder="选择班级"
              size="small"
              style="width: 160px"
              @change="handleClassSelect"
            >
              <el-option
                v-for="classOption in schoolClassOptions"
                :key="classOption.id"
                :label="`${classOption.class_name}${classOption.grade ? ' · ' + classOption.grade : ''}${userStore.boundClassId === classOption.id ? ' (班主任)' : ''}`"
                :value="classOption.id"
              />
            </el-select>
            <el-tag
              v-if="userStore.isHomeroomForSelected"
              size="small"
              type="warning"
              effect="light"
              style="margin-left: 6px"
            >班主任</el-tag>
          </div>
        </div>

        <div class="top-bar-right">
          <div v-if="isTeacherRole && userStore.isHomeroomForSelected" class="teacher-view-toggle" @click="switchTeacherView">
            <el-tag :type="teacherViewMode === 'frontend' ? 'success' : 'primary'" effect="light">
              {{ teacherViewLabel }}
            </el-tag>
            <span class="teacher-view-hint">点击切换</span>
          </div>
          <el-dropdown trigger="click" @command="handleAccountCommand">
            <div class="account-menu-trigger">
              <el-avatar :size="32" :style="{ background: '#1E6FD9' }">
                {{ (userStore.name ?? 'U').charAt(0).toUpperCase() }}
              </el-avatar>
              <span class="account-name">{{ userStore.name ?? userStore.email }}</span>
              <el-icon><ArrowDown /></el-icon>
            </div>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item disabled>
                  角色：{{ activeRoleLabel }}
                </el-dropdown-item>
                <el-dropdown-item :command="'change-password'">
                  <el-icon><Lock /></el-icon>
                  修改密码
                </el-dropdown-item>
                <el-dropdown-item :command="'edit-profile'">
                  <el-icon><User /></el-icon>
                  修改个人信息
                </el-dropdown-item>
                <el-dropdown-item divided v-if="roleSwitchOptions.length > 1">
                  <el-dropdown trigger="hover" placement="right-start">
                    <div class="role-switch-entry">
                      <el-icon><Refresh /></el-icon>
                      切换角色
                    </div>
                    <template #dropdown>
                      <el-dropdown-menu>
                        <el-dropdown-item
                          v-for="roleOption in roleSwitchOptions"
                          :key="roleOption.role"
                          :disabled="roleOption.role === userStore.role"
                          @click="handleRoleSwitch(roleOption.role)"
                        >
                          {{ roleOption.label }}
                          <span v-if="roleOption.role === userStore.role" class="role-current-hint">
                            (当前)
                          </span>
                        </el-dropdown-item>
                      </el-dropdown-menu>
                    </template>
                  </el-dropdown>
                </el-dropdown-item>
                <el-dropdown-item divided :command="'logout'">
                  <el-icon><SwitchButton /></el-icon>
                  退出登录
                </el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
        </div>
      </el-header>

      <el-main class="page-viewport">
        <router-view />
      </el-main>
    </el-container>

    <!-- 修改密码对话框 -->
    <el-dialog
      v-model="passwordDialogVisible"
      title="修改密码"
      width="420px"
      :close-on-click-modal="false"
      destroy-on-close
    >
      <el-form ref="passwordFormRef" :model="passwordForm" :rules="passwordRules" label-width="90px">
        <el-form-item label="当前密码" prop="oldPassword">
          <el-input
            v-model="passwordForm.oldPassword"
            type="password"
            show-password
            placeholder="请输入当前密码"
          />
        </el-form-item>
        <el-form-item label="新密码" prop="newPassword">
          <el-input
            v-model="passwordForm.newPassword"
            type="password"
            show-password
            placeholder="至少 6 位"
          />
        </el-form-item>
        <el-form-item label="确认新密码" prop="confirmPassword">
          <el-input
            v-model="passwordForm.confirmPassword"
            type="password"
            show-password
            placeholder="再次输入新密码"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="passwordDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="passwordSubmitting" @click="submitPasswordChange">
          确定修改
        </el-button>
      </template>
    </el-dialog>

    <!-- 修改个人信息对话框 -->
    <el-dialog
      v-model="profileDialogVisible"
      title="修改个人信息"
      width="420px"
      :close-on-click-modal="false"
      destroy-on-close
    >
      <el-form label-width="90px">
        <el-form-item label="姓名">
          <el-input v-model="profileForm.realName" placeholder="显示在头像与顶栏的名字" maxlength="20" />
        </el-form-item>
        <el-form-item label="手机号">
          <el-input v-model="profileForm.phone" placeholder="用于手机号登录" maxlength="20" />
        </el-form-item>
        <el-form-item label=" ">
          <span class="profile-save-hint">保存后立即生效；手机号登录在下次登录时使用新号码</span>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="profileDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="profileSubmitting" @click="submitProfileChange">
          保存
        </el-button>
      </template>
    </el-dialog>
  </el-container>
</template>

<style scoped>
.platform-shell {
  height: 100vh;
  width: 100vw;
}

.nav-sidebar {
  background: #001529;
  display: flex;
  flex-direction: column;
  overflow-x: hidden;
}

.brand-banner {
  height: 60px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  background: #001020;
  color: #fff;
  font-size: 16px;
  font-weight: 600;
  letter-spacing: 1px;
}

.brand-emblem {
  font-size: 22px;
}

.role-nav-menu {
  flex: 1;
  border-right: none;
}

.top-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: #fff;
  border-bottom: 1px solid #ebeef5;
  padding: 0 24px;
}

.top-bar-left {
  display: flex;
  align-items: center;
  gap: 20px;
}

.school-identity,
.class-identity {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 13px;
  color: #606266;
}

.class-picker {
  display: flex;
  align-items: center;
  gap: 6px;
}

.top-bar-right {
  display: flex;
  align-items: center;
}

.account-menu-trigger {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  padding: 4px 8px;
  border-radius: 6px;
  transition: background 0.2s;
}

.account-menu-trigger:hover {
  background: #f5f7fa;
}

.account-name {
  font-size: 14px;
  color: #303133;
}

.profile-save-hint {
  font-size: 12px;
  color: #909399;
  line-height: 1.4;
}
.page-viewport {
  background: #f5f7fa;
  padding: 20px;
  overflow-y: auto;
}

.role-switch-entry {
  display: flex;
  align-items: center;
  gap: 6px;
  width: 100%;
}

.role-current-hint {
  color: #909399;
  font-size: 12px;
  margin-left: 8px;
}

.teacher-view-toggle {
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  padding: 4px 10px;
  border-radius: 6px;
  transition: background 0.2s;
  margin-right: 16px;
}

.teacher-view-toggle:hover {
  background: #f0f5ff;
}

.teacher-view-hint {
  font-size: 11px;
  color: #909399;
}

.mobile-nav-toggle {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 8px;
  cursor: pointer;
  color: #303133;
  margin-right: 8px;
}
.mobile-nav-toggle:hover { background: #f0f5ff; }

.nav-sidebar-drawer {
  height: 100%;
  width: 100%;
}

/* 移动端媒体查询 */
@media (max-width: 768px) {
  .top-bar-left { gap: 8px; }
  .school-identity, .class-identity { display: none; }
  .account-name { display: none; }
  .teacher-view-hint { display: none; }
  .page-viewport { padding: 12px; }
  .top-bar-right { gap: 6px; }
}
</style>