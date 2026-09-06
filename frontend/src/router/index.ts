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

const roleHomeMap: Record<Role, string> = {
  sys_admin: '/admin-edu/dashboard',
  school_admin: '/admin-school/dashboard',
  teacher: '/teacher/frontend/homework',
}

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
        return userStore.role ? roleHomeMap[userStore.role] : '/login'
      },
      children: navMenus.map((item) => ({
        path: item.path.replace(/^\/+/, ''),
        name: item.path,
        component: item.component,
        meta: { roles: item.roles, title: item.title, icon: item.icon },
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

router.afterEach((to) => {
  if (to.meta.title) {
    document.title = `${to.meta.title} - 校园信息化服务平台`
  }
})

export default router
