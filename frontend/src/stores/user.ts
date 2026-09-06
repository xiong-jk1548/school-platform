import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { supabase } from '@/api/supabase'
import type { Role } from '@/types'

export type { Role }

export const useUserStore = defineStore(
  'user',
  () => {
    const id = ref<string | null>(null)
    const email = ref<string | null>(null)
    const phone = ref<string | null>(null)
    const name = ref<string | null>(null)
    const role = ref<Role | null>(null)
    const schoolId = ref<string | null>(null)
    // 档案里绑定的班级（只有班主任才有值；学科教师为 null）
    const boundClassId = ref<string | null>(null)
    const boundClassName = ref<string | null>(null)

    // 当前"正在看"的班级（MainLayout 里班级下拉选择器写入 localStorage，任何老师都可以切学校内任何班）
    const selectedClassId = ref<string | null>(null)
    const selectedClassName = ref<string | null>(null)

    const isLoggedIn = computed(() => !!id.value && !!role.value)

    /** 当前选中班级是否是自己绑定的班级（只有在自己的班里才能看到后端菜单） */
    const isHomeroomForSelected = computed(
      () => !!boundClassId.value && selectedClassId.value === boundClassId.value,
    )

    /** 切换到某个班级 */
    function setSelectedClass(id: string, className: string) {
      selectedClassId.value = id
      selectedClassName.value = className
      localStorage.setItem('MOCK_SELECTED_CLASS', id)
      localStorage.setItem('MOCK_SELECTED_CLASS_NAME', className)
    }

    async function login(emailInput: string, password: string): Promise<void> {
      const { data, error } = await supabase.auth.signInWithPassword({
        email: emailInput,
        password,
      })
      if (error) throw error
      if (!data.user) throw new Error('登录失败：未获取到用户信息')

      const userRole = (data.user.user_metadata?.role ?? null) as Role | null
      id.value = data.user.id
      email.value = data.user.email ?? null
      phone.value = (data.user.user_metadata?.phone ?? null) as string | null
      name.value = (data.user.user_metadata?.name ?? data.user.email ?? null) as string | null
      role.value = userRole
      schoolId.value = (data.user.user_metadata?.school_id ?? null) as string | null
      boundClassId.value = (data.user.user_metadata?.class_id ?? null) as string | null
      boundClassName.value = (data.user.user_metadata?.class_name ?? null) as string | null
      // 初始化 selectedClass：优先用上次选中的；否则默认 bound
      const storedId = localStorage.getItem('MOCK_SELECTED_CLASS')
      const storedName = localStorage.getItem('MOCK_SELECTED_CLASS_NAME')
      if (storedId) {
        selectedClassId.value = storedId
        selectedClassName.value = storedName ?? ''
      } else {
        selectedClassId.value = boundClassId.value
        selectedClassName.value = boundClassName.value
      }
    }

    async function logout(): Promise<void> {
      await supabase.auth.signOut()
      $reset()
    }

    async function syncFromSession(): Promise<void> {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      if (!session?.user) return
      const user = session.user
      id.value = user.id
      email.value = user.email ?? null
      phone.value = (user.user_metadata?.phone ?? null) as string | null
      name.value = (user.user_metadata?.name ?? user.email ?? null) as string | null
      role.value = (user.user_metadata?.role ?? null) as Role | null
      schoolId.value = (user.user_metadata?.school_id ?? null) as string | null
      boundClassId.value = (user.user_metadata?.class_id ?? null) as string | null
      boundClassName.value = (user.user_metadata?.class_name ?? null) as string | null

      const storedId = localStorage.getItem('MOCK_SELECTED_CLASS')
      const storedName = localStorage.getItem('MOCK_SELECTED_CLASS_NAME')
      if (storedId) {
        selectedClassId.value = storedId
        selectedClassName.value = storedName ?? ''
      } else {
        selectedClassId.value = boundClassId.value
        selectedClassName.value = boundClassName.value
      }
    }

    function $reset() {
      id.value = null
      email.value = null
      phone.value = null
      name.value = null
      role.value = null
      schoolId.value = null
      boundClassId.value = null
      boundClassName.value = null
      selectedClassId.value = null
      selectedClassName.value = null
    }

    // 兼容旧代码引用的 classId / className
    const classId = computed(() => selectedClassId.value ?? boundClassId.value)
    const className = computed(() => selectedClassName.value ?? boundClassName.value)

    return {
      id,
      email,
      phone,
      name,
      role,
      schoolId,
      boundClassId,
      boundClassName,
      selectedClassId,
      selectedClassName,
      isLoggedIn,
      isHomeroomForSelected,
      setSelectedClass,
      login,
      logout,
      syncFromSession,
      $reset,
      classId,
      className,
    }
  },
  {
    persist: {
      pick: [
        'id', 'email', 'phone', 'name', 'role', 'schoolId',
        'boundClassId', 'boundClassName',
        'selectedClassId', 'selectedClassName',
      ],
    },
  },
)
