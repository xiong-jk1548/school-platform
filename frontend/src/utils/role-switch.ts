import { useUserStore } from '@/stores/user'
import type { Role } from '@/types'

const ROLE_LABELS = {
  sys_admin: '教育局管理员',
  school_admin: '学校管理员',
  teacher: '教师',
} as const

export interface RoleOption {
  role: Role
  label: string
  schoolId?: string | null
  classId?: string | null
  className?: string | null
}

/**
 * 返回当前用户可以"切换"的候选角色列表。
 * - 始终包含"当前活跃角色"
 * - 与真实身份不同时，附带一条"真实身份"选项，便于切回
 * - sys_admin / school_admin 可以代理其他角色预览数据
 * @returns RoleOption[] 已按 role 去重的候选列表；不会出现两条同 role 的项
 */
export function getSwitchableRoles(): RoleOption[] {
  const userStore = useUserStore()
  const roleOptions: RoleOption[] = []
  const realRole = userStore.realRole
  const activeRole = userStore.role

  /**
   * 追加一条候选角色。
   * @param role 角色标识
   * @param extraLabel 追加在角色名后的说明后缀，如 ' (代理)'
   */
  const pushOption = (role: Role, extraLabel = '') => {
    roleOptions.push({
      role,
      label: ROLE_LABELS[role] + extraLabel,
      schoolId: userStore.schoolId,
      classId: userStore.classId,
      className: userStore.className,
    })
  }

  // 当前活跃
  if (activeRole) pushOption(activeRole, activeRole === realRole ? ' (当前)' : ' (代理中)')

  // 真实角色（与活跃不同时，提示可以切回去）
  if (realRole && realRole !== activeRole) pushOption(realRole, ' (真实身份)')

  // 代理：sys_admin 体验 school_admin
  if (realRole === 'sys_admin' && activeRole !== 'school_admin' && userStore.schoolId) {
    pushOption('school_admin', ' (测试)')
  }
  // 代理：school_admin 代理教师看本班
  if (realRole === 'school_admin' && activeRole !== 'teacher') pushOption('teacher', ' (代理)')

  // 去重：同一角色可能被上面多条分支推到，只保留最先出现的那条（后缀信息更贴合当前状态）
  const seenRoles = new Set<string>()
  return roleOptions.filter((option) => {
    if (seenRoles.has(option.role)) return false
    seenRoles.add(option.role)
    return true
  })
}

/**
 * 切换当前活跃角色并整页重载。
 * - 切到与真实身份一致：清掉 MOCK_ROLE_OVERRIDE，回到原身份
 * - 切到其他角色：写入 MOCK_ROLE_OVERRIDE，刷新后由 syncFromSession 还原
 * @param newRole 目标角色
 * @returns 无（副作用：写 localStorage 并 window.location.reload()）
 */
export function switchRole(newRole: Role) {
  const userStore = useUserStore()
  if (newRole === userStore.realRole) {
    localStorage.removeItem('MOCK_ROLE_OVERRIDE')
  } else {
    localStorage.setItem('MOCK_ROLE_OVERRIDE', newRole)
  }
  userStore.role = newRole
  window.location.reload()
}