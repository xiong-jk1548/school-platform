import { createRouter, createWebHistory } from 'vue-router'
import type { RouteRecordRaw } from 'vue-router'
import MainLayout from '@/layouts/MainLayout.vue'
import LoginLayout from '@/layouts/LoginLayout.vue'
import { useUserStore } from '@/stores/user'
import { supabase } from '@/api/supabase'
import type { Role } from '@/types'
import { navMenus } from './menus'

declare module 'vue-router' {
  interface RouteMeta {
    roles?: Role[]
    title?: string
    icon?: string
  }
}

/** 每种角色登录后各自的首页；命中不到（role 为空或非法值）时由调用方兜底回 /login */
const roleHomeMap: Record<string, string> = {
  sys_admin: '/admin-edu/dashboard',
  school_admin: '/admin-school/dashboard',
  teacher: '/teacher/frontend/homework',
}

/**
 * 按侧边栏菜单表 navMenus 生成受保护区域的路由表，保证"菜单可见 = 路由可达"。
 * @returns RouteRecordRaw[] 登录页 + 主布局（children 为全部菜单页）+ 未匹配路径兜底
 */
function buildRoutes(): RouteRecordRaw[] {
  const routes: RouteRecordRaw[] = [
    {
      path: '/login',
      name: 'Login',
      component: LoginLayout,
      meta: { title: '登录' },
    },
    {
      path: '/',
      component: MainLayout,
      redirect: () => {
        const userStore = useUserStore()
        if (!userStore.role) return '/login'
        return roleHomeMap[userStore.role] ?? '/login'
      },
      children: navMenus.map((menu) => ({
        path: menu.path.replace(/^\/+/, ''),
        name: menu.path,
        component: menu.component,
        meta: { roles: menu.roles, title: menu.title, icon: menu.icon },
      })),
    },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ]
  return routes
}

const router = createRouter({
  history: createWebHistory(),
  routes: buildRoutes(),
})

/**
 * 全局前置守卫：先确认 Supabase 会话，再校验角色准入。
 * @param to 即将进入的目标路由（读 to.path / to.meta.roles / to.fullPath）
 * @returns true 放行；返回路径或对象表示重定向（未登录时会带上 redirect 便于登录后回跳）
 *
 * 注意：user_metadata.role 若为空会直接踢回登录页——角色为空时侧边栏菜单过滤后
 * 为空数组，页面渲染不出内容，容易表现为"登录成功却白屏"。
 */
router.beforeEach(async (to) => {
  const userStore = useUserStore()

  if (to.path === '/login') {
    if (userStore.isLoggedIn) return '/'
    return true
  }

  const {
    data: { session },
  } = await supabase.auth.getSession()

  if (!session) {
    await userStore.logout()
    return { path: '/login', query: { redirect: to.fullPath } }
  }

  if (!userStore.isLoggedIn) {
    await userStore.syncFromSession()
  }

  if (!userStore.role) {
    await userStore.logout()
    return { path: '/login', query: { redirect: to.fullPath } }
  }

  if (to.meta.roles && to.meta.roles.length > 0) {
    if (!to.meta.roles.includes(userStore.role)) {
      return roleHomeMap[userStore.role]
    }
  }

  return true
})

/**
 * 全局后置钩子：把当前页标题写进浏览器标签，格式为「页面名 - 智慧校园管理平台」。
 * @param to 已完成导航的目标路由
 * @returns 无
 */
router.afterEach((to) => {
  if (to.meta.title) {
    document.title = `${to.meta.title} - 智慧校园管理平台`
  }
})

export default router