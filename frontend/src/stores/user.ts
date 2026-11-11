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
    // 真实角色（来自 JWT metadata，不可被切换）
    const realRole = ref<Role | null>(null)
    // 当前活跃角色（可被 role-switch 覆盖；reload 后由 MOCK_ROLE_OVERRIDE 还原）
    const role = ref<Role | null>(null)
    const schoolId = ref<string | null>(null)
    const schoolName = ref<string | null>(null)
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

    /**
     * 切换当前正在查看的班级。
     * @param id 班级主键 classes.id
     * @param className 班级显示名，用于顶栏与导出文件名
     * @returns 无（同时写入 localStorage，供刷新后还原）
     */
    function setSelectedClass(id: string, className: string) {
      selectedClassId.value = id
      selectedClassName.value = className
      localStorage.setItem('MOCK_SELECTED_CLASS', id)
      localStorage.setItem('MOCK_SELECTED_CLASS_NAME', className)
    }

    /**
     * 退出登录：清掉 Supabase 会话并重置 store（persist 会把空值同步回 localStorage）。
     * @returns Promise<void>
     */
    async function logout(): Promise<void> {
      await supabase.auth.signOut()
      $reset()
    }

    /**
     * 从 Supabase 会话里把用户档案同步进 store；登录页与路由守卫都走这里。
     * @returns Promise<void>，会话不存在时直接返回、不改动任何字段
     *
     * 注意：角色只认 sys_admin / school_admin / teacher 三种，user_metadata.role 写成别的值
     * （例如 super_admin）时菜单会被过滤成空数组，表现为"登录成功却白屏"。
     */
    async function syncFromSession(): Promise<void> {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      if (!session?.user) return
      const sessionUser = session.user
      id.value = sessionUser.id
      email.value = sessionUser.email ?? null
      phone.value = (sessionUser.user_metadata?.phone ?? null) as string | null
      name.value = (sessionUser.user_metadata?.real_name ?? sessionUser.user_metadata?.name ?? sessionUser.email ?? null) as string | null
      // 真实角色写单独 ref（持久）
      realRole.value = (sessionUser.user_metadata?.role ?? null) as Role | null
      // 当前活跃角色：默认真实角色，但允许被 MOCK_ROLE_OVERRIDE 覆盖（保证切换角色 + 刷新页面后仍生效）
      const roleOverride = localStorage.getItem('MOCK_ROLE_OVERRIDE') as Role | null
      role.value = (roleOverride ?? realRole.value) as Role | null
      schoolId.value = (sessionUser.user_metadata?.school_id ?? null) as string | null
      boundClassId.value = (sessionUser.user_metadata?.class_id ?? null) as string | null
      boundClassName.value = (sessionUser.user_metadata?.class_name ?? null) as string | null

      // 补学校显示名：schools 表既有 school_name，也加了兼容列 name（见命名不一致那次的教训），
      // 两个都取一遍，避免顶栏只显示出一串 UUID
      if (schoolId.value) {
        const { data: schoolRows } = await supabase
          .from('schools')
          .select('school_name, name')
          .eq('id', schoolId.value)
          .limit(1)
        schoolName.value = ((schoolRows?.[0] as any)?.name ?? (schoolRows?.[0] as any)?.school_name ?? null) as string | null
      } else {
        schoolName.value = null
      }

      // 初始化 selectedClass：优先用上次选中的；否则默认绑定的班级
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

    /**
     * 把 store 全部字段清空。
     * @returns 无
     */
    function $reset() {
      id.value = null
      email.value = null
      phone.value = null
      name.value = null
      realRole.value = null
      role.value = null
      schoolId.value = null
      schoolName.value = null
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
      realRole,
      role,
      schoolId,
      schoolName,
      boundClassId,
      boundClassName,
      selectedClassId,
      selectedClassName,
      isLoggedIn,
      isHomeroomForSelected,
      setSelectedClass,
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
        'id', 'email', 'phone', 'name', 'realRole', 'role', 'schoolId', 'schoolName',
        'boundClassId', 'boundClassName',
        'selectedClassId', 'selectedClassName',
      ],
    },
  },
)