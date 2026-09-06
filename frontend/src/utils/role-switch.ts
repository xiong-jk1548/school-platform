import { useUserStore } from '@/stores/user'

const ROLE_LABELS = {
  sys_admin: '教育局管理员',
  school_admin: '学校管理员',
  teacher: '教师',
} as const

export interface RoleOption {
  role: 'sys_admin' | 'school_admin' | 'teacher'
  label: string
  schoolId?: string | null
  classId?: string | null
  className?: string | null
}

export function getSwitchableRoles(): RoleOption[] {
  const store = useUserStore()
  const opts: RoleOption[] = []

  opts.push({
    role: store.role!,
    label: ROLE_LABELS[store.role!],
    schoolId: store.schoolId,
    classId: store.classId,
    className: store.className,
  })

  if (store.role === 'sys_admin' && store.schoolId) {
    opts.push({
      role: 'school_admin',
      label: '学校管理员（测试）',
      schoolId: store.schoolId,
    })
  }
  if (store.role === 'school_admin' && store.classId) {
    opts.push({
      role: 'teacher',
      label: '教师（测试）',
      schoolId: store.schoolId,
      classId: store.classId,
    })
  }

  return opts
}

export function switchRole(newRole: 'sys_admin' | 'school_admin' | 'teacher') {
  const store = useUserStore()
  const key = 'MOCK_ROLE_OVERRIDE'
  localStorage.setItem(key, newRole)
  store.role = newRole as any
  window.location.reload()
}
