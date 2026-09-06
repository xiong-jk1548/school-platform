<script setup lang="ts">
import { computed, ref, watch, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessageBox } from 'element-plus'
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
} from '@element-plus/icons-vue'

const userStore = useUserStore()
const route = useRoute()
const router = useRouter()

const sidebarWidth = '220px'

// 响应式：移动端用抽屉
const isMobile = ref(false)
const drawerVisible = ref(false)
function checkMobile() {
  isMobile.value = window.innerWidth < 768
}
onMounted(() => {
  checkMobile()
  window.addEventListener('resize', checkMobile)
})
onUnmounted(() => window.removeEventListener('resize', checkMobile))

const TEACHER_VIEW_KEY = 'MOCK_TEACHER_VIEW'
const teacherView = ref<TeacherView>(localStorage.getItem(TEACHER_VIEW_KEY) as TeacherView || 'frontend')

watch(teacherView, (v) => {
  localStorage.setItem(TEACHER_VIEW_KEY, v)
})

// 学校里所有班级 — 给教师下拉选择
const schoolClasses = ref<{ id: string; class_name: string; grade?: string; homeroom_teacher_id?: string | null }[]>([])
async function loadSchoolClasses() {
  if (!userStore.schoolId) return
  try {
    const { data } = await supabase
      .from('classes')
      .select('id, class_name, grade, homeroom_teacher_id')
      .eq('school_id', userStore.schoolId)
    schoolClasses.value = (data ?? []) as any
  } catch { /* ignore */ }
}

watch(() => userStore.role, loadSchoolClasses)
watch(() => userStore.schoolId, loadSchoolClasses)
onMounted(loadSchoolClasses)

async function onClassChange(classId: string) {
  const cls = schoolClasses.value.find((c) => c.id === classId)
  if (!cls) return
  userStore.setSelectedClass(cls.id, cls.class_name)
  // 如果正在看后端但切到的不是自己的班，自动切回前端
  if (teacherView.value === 'backend' && !userStore.isHomeroomForSelected) {
    teacherView.value = 'frontend'
  }
}

const displayMenus = computed(() => {
  return navMenus.filter((item) => {
    if (!userStore.role || !item.roles.includes(userStore.role)) return false
    if (userStore.role === 'teacher') {
      if (item.teacherView && !item.teacherView.includes(teacherView.value)) return false
      // 后端菜单仅班主任在自己的班里可见
      if (teacherView.value === 'backend' && (item.teacherView?.includes('backend'))) {
        if (!userStore.isHomeroomForSelected) return false
      }
    }
    return true
  })
})

const switchableRoles = computed(() => getSwitchableRoles())
const currentRoleLabel = computed(() => {
  const map = { sys_admin: '教育局管理员', school_admin: '学校管理员', teacher: '教师' }
  return map[userStore.role as keyof typeof map] ?? ''
})

const isTeacher = computed(() => userStore.role === 'teacher')
const viewLabel = computed(() => (teacherView.value === 'frontend' ? '班级前端' : '班级后台'))

function toggleTeacherView() {
  teacherView.value = teacherView.value === 'frontend' ? 'backend' : 'frontend'
  // 切换后跳转到对应视图的第一个菜单
  const firstMenu = displayMenus.value[0]
  if (firstMenu && route.path !== firstMenu.path) {
    router.push(firstMenu.path)
  }
}

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

function handleCommand(cmd: string) {
  if (cmd === 'logout') {
    handleLogout()
  }
}

function onSwitchRole(role: 'sys_admin' | 'school_admin' | 'teacher') {
  switchRole(role)
}
</script>

<template>
  <el-container class="main-layout">
    <!-- 桌面端侧边栏 -->
    <el-aside v-if="!isMobile" :width="sidebarWidth" class="sidebar">
      <div class="logo-area">
        <span class="logo-icon">🎓</span>
        <span class="logo-text">校园信息化</span>
      </div>
      <el-menu
        :default-active="route.path"
        :router="true"
        background-color="#001529"
        text-color="#c8d6e5"
        active-text-color="#1E6FD9"
        class="nav-menu"
      >
        <template v-for="menu in displayMenus" :key="menu.path">
          <el-menu-item :index="menu.path">
            <el-icon v-if="menu.icon"><component :is="menu.icon" /></el-icon>
            <span>{{ menu.title }}</span>
          </el-menu-item>
        </template>
      </el-menu>
    </el-aside>

    <!-- 移动端抽屉 -->
    <el-drawer
      v-if="isMobile"
      v-model="drawerVisible"
      direction="ltr"
      :size="260"
      :show-close="false"
      :with-header="false"
      class="mobile-drawer"
    >
      <div class="sidebar sidebar-drawer">
        <div class="logo-area">
          <span class="logo-icon">🎓</span>
          <span class="logo-text">校园信息化</span>
        </div>
        <el-menu
          :default-active="route.path"
          :router="true"
          background-color="#001529"
          text-color="#c8d6e5"
          active-text-color="#1E6FD9"
          class="nav-menu"
          @select="drawerVisible = false"
        >
          <template v-for="menu in displayMenus" :key="menu.path">
            <el-menu-item :index="menu.path">
              <el-icon v-if="menu.icon"><component :is="menu.icon" /></el-icon>
              <span>{{ menu.title }}</span>
            </el-menu-item>
          </template>
        </el-menu>
      </div>
    </el-drawer>

    <el-container>
      <el-header class="header">
        <div class="header-left">
          <el-icon v-if="isMobile" class="mobile-menu-btn" @click="drawerVisible = true">
            <svg viewBox="0 0 1024 1024" width="20" height="20"><path fill="currentColor" d="M128 192h768v64H128zm0 320h768v64H128zm0 320h768v64H128z"/></svg>
          </el-icon>
          <el-breadcrumb separator="/">
            <el-breadcrumb-item :to="{ path: '/' }">
              {{ route.meta.title ?? '首页' }}
            </el-breadcrumb-item>
          </el-breadcrumb>
          <div class="school-info" v-if="userStore.role === 'school_admin'">
            <el-icon><School /></el-icon>
            <span>{{ userStore.schoolId ?? '未关联学校' }}</span>
          </div>
          <!-- 教师：班级下拉选择器 -->
          <div class="class-select-wrap" v-if="userStore.role === 'teacher'">
            <el-icon style="color:#2B5CE6"><Reading /></el-icon>
            <el-select
              :model-value="userStore.selectedClassId"
              placeholder="选择班级"
              size="small"
              style="width: 160px"
              @change="onClassChange"
            >
              <el-option
                v-for="c in schoolClasses"
                :key="c.id"
                :label="`${c.class_name}${c.grade ? ' · ' + c.grade : ''}${userStore.boundClassId === c.id ? ' (班主任)' : ''}`"
                :value="c.id"
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

        <div class="header-right">
          <div v-if="isTeacher && userStore.isHomeroomForSelected" class="view-switch" @click="toggleTeacherView">
            <el-tag :type="teacherView === 'frontend' ? 'success' : 'primary'" effect="light">
              {{ viewLabel }}
            </el-tag>
            <span class="view-switch-hint">点击切换</span>
          </div>
          <el-dropdown trigger="click" @command="handleCommand">
            <div class="user-dropdown-trigger">
              <el-avatar :size="32" :style="{ background: '#1E6FD9' }">
                {{ (userStore.name ?? 'U').charAt(0).toUpperCase() }}
              </el-avatar>
              <span class="user-name">{{ userStore.name ?? userStore.email }}</span>
              <el-icon><ArrowDown /></el-icon>
            </div>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item disabled>
                  角色：{{ currentRoleLabel }}
                </el-dropdown-item>
                <el-dropdown-item :command="'change-password'" disabled>
                  <el-icon><Lock /></el-icon>
                  修改密码
                </el-dropdown-item>
                <el-dropdown-item divided v-if="switchableRoles.length > 1">
                  <el-dropdown trigger="hover" placement="right-start">
                    <div class="role-switch-trigger">
                      <el-icon><Refresh /></el-icon>
                      切换角色
                    </div>
                    <template #dropdown>
                      <el-dropdown-menu>
                        <el-dropdown-item
                          v-for="opt in switchableRoles"
                          :key="opt.role"
                          :disabled="opt.role === userStore.role"
                          @click="onSwitchRole(opt.role)"
                        >
                          {{ opt.label }}
                          <span v-if="opt.role === userStore.role" class="role-current-tag">
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

      <el-main class="main-content">
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<style scoped>
.main-layout {
  height: 100vh;
  width: 100vw;
}

.sidebar {
  background: #001529;
  display: flex;
  flex-direction: column;
  overflow-x: hidden;
}

.logo-area {
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

.logo-icon {
  font-size: 22px;
}

.nav-menu {
  flex: 1;
  border-right: none;
}

.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: #fff;
  border-bottom: 1px solid #ebeef5;
  padding: 0 24px;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 20px;
}

.school-info,
.class-info {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 13px;
  color: #606266;
}

.class-select-wrap {
  display: flex;
  align-items: center;
  gap: 6px;
}

.header-right {
  display: flex;
  align-items: center;
}

.user-dropdown-trigger {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  padding: 4px 8px;
  border-radius: 6px;
  transition: background 0.2s;
}

.user-dropdown-trigger:hover {
  background: #f5f7fa;
}

.user-name {
  font-size: 14px;
  color: #303133;
}

.main-content {
  background: #f5f7fa;
  padding: 20px;
  overflow-y: auto;
}

.role-switch-trigger {
  display: flex;
  align-items: center;
  gap: 6px;
  width: 100%;
}

.role-current-tag {
  color: #909399;
  font-size: 12px;
  margin-left: 8px;
}

.view-switch {
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  padding: 4px 10px;
  border-radius: 6px;
  transition: background 0.2s;
  margin-right: 16px;
}

.view-switch:hover {
  background: #f0f5ff;
}

.view-switch-hint {
  font-size: 11px;
  color: #909399;
}

.mobile-menu-btn {
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
.mobile-menu-btn:hover { background: #f0f5ff; }

.sidebar-drawer {
  height: 100%;
  width: 100%;
}

/* 移动端媒体查询 */
@media (max-width: 768px) {
  .header-left { gap: 8px; }
  .school-info, .class-info { display: none; }
  .user-name { display: none; }
  .view-switch-hint { display: none; }
  .main-content { padding: 12px; }
  .header-right { gap: 6px; }
}
</style>
