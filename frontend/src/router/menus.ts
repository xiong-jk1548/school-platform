import type { Component } from 'vue'
import type { Role } from '@/types'

/** 教师角色的视图模式：frontend=班级前端（日常使用），backend=班级后台（数据管理） */
export type TeacherView = 'frontend' | 'backend'

export interface MenuItem {
  path: string
  title: string
  icon?: string
  roles: Role[]
  /** 该菜单在教师角色下可见的视图模式；不写表示 frontend / backend 都可见 */
  teacherView?: TeacherView[]
  component: () => Promise<Component>
}

// 一次性登记 views 与 modules 两个目录下的全部页面组件（懒加载，不 eager）
const pageModules = import.meta.glob<Record<string, () => Promise<Component>>>(
  ['@/views/**/*.vue', '@/modules/**/*.vue'],
  { eager: false, import: 'default' },
)

/**
 * 把菜单里的相对路径解析成组件的懒加载工厂。
 * @param relativePath 相对 views/ 或 modules/ 的页面路径，例如 'teacher/Leaderboard.vue'
 * @returns () => Promise<Component> 该页面的动态 import 工厂，直接赋给 MenuItem.component
 * @throws Error 两个目录都登记不到该路径时抛出（否则点菜单必然白屏，故让它尽早暴露）
 */
function loadView(relativePath: string) {
  const viewKey = `/src/views/${relativePath}`
  const moduleKey = `/src/modules/${relativePath}`
  const loader =
    (pageModules as unknown as Record<string, () => Promise<Component>>)[viewKey] ??
    (pageModules as unknown as Record<string, () => Promise<Component>>)[moduleKey]
  if (!loader) throw new Error(`找不到视图文件: ${relativePath}`)
  return loader
}

export const navMenus: MenuItem[] = [
  { path: '/admin-edu/dashboard', title: '工作台', icon: 'HomeFilled', roles: ['sys_admin'], component: loadView('admin-edu/Dashboard.vue') },
  { path: '/admin-edu/schools', title: '学校管理', icon: 'School', roles: ['sys_admin'], component: loadView('admin-edu/Schools.vue') },
  { path: '/admin-edu/points-config', title: '管理员账号', icon: 'User', roles: ['sys_admin'], component: loadView('admin-edu/PointsConfig.vue') },
  { path: '/admin-edu/reports', title: '统计报表', icon: 'DataAnalysis', roles: ['sys_admin'], component: loadView('admin-edu/Reports.vue') },

  { path: '/admin-school/dashboard', title: '工作台', icon: 'HomeFilled', roles: ['school_admin'], component: loadView('admin-school/Dashboard.vue') },
  { path: '/admin-school/classes', title: '班级管理', icon: 'Files', roles: ['school_admin'], component: loadView('school/class-manage.vue') },
  { path: '/admin-school/teachers', title: '教师管理', icon: 'User', roles: ['school_admin'], component: loadView('school/teacher-user.vue') },
  { path: '/admin-school/student-import', title: '导入学生', icon: 'UploadFilled', roles: ['school_admin'], component: loadView('school/student-import.vue') },
  { path: '/admin-school/students', title: '学生列表', icon: 'Avatar', roles: ['school_admin'], component: loadView('school/student-list.vue') },
  { path: '/admin-school/logs', title: '积分流水', icon: 'Tickets', roles: ['school_admin'], component: loadView('school/log-list.vue') },
  { path: '/admin-school/inspection', title: '班级检查扣分', icon: 'TrendCharts', roles: ['school_admin'], component: loadView('school/inspection-deduct.vue') },

  // 教师 · 前端（班级日常使用 — 高频在上，大件作业/借阅放底部）
  { path: '/teacher/frontend/random-picker', title: '随机点名', icon: 'MagicStick', roles: ['teacher'], teacherView: ['frontend'], component: loadView('teacher/RandomPicker.vue') },
  { path: '/teacher/frontend/leaderboard', title: '积分排行榜', icon: 'TrendCharts', roles: ['teacher'], teacherView: ['frontend'], component: loadView('teacher/Leaderboard.vue') },
  { path: '/teacher/frontend/honor-wall', title: '班级荣誉墙', icon: 'Medal', roles: ['teacher'], teacherView: ['frontend'], component: loadView('teacher/HonorWall.vue') },
  { path: '/teacher/frontend/award-register', title: '获奖登记', icon: 'Trophy', roles: ['teacher'], teacherView: ['frontend'], component: loadView('teacher/AwardRegister.vue') },
  { path: '/teacher/frontend/homework', title: '作业登记', icon: 'EditPen', roles: ['teacher'], teacherView: ['frontend'], component: loadView('homework/views/HomeworkBoard.vue') },
  { path: '/teacher/frontend/borrow', title: '物品借阅', icon: 'Goods', roles: ['teacher'], teacherView: ['frontend'], component: () => import('@/modules/borrow/index').then(m => m.default.component()) },

  // 教师 · 后台（数据管理）
  { path: '/teacher/backend/dashboard', title: '工作台', icon: 'HomeFilled', roles: ['teacher'], teacherView: ['backend'], component: loadView('teacher/Dashboard.vue') },
  { path: '/teacher/backend/my-class', title: '我的班级', icon: 'Files', roles: ['teacher'], teacherView: ['backend'], component: loadView('school/class-manage.vue') },
  { path: '/teacher/backend/students', title: '学生管理', icon: 'Avatar', roles: ['teacher'], teacherView: ['backend'], component: loadView('teacher/student-list.vue') },
  { path: '/teacher/backend/grade-dashboard', title: '成绩仪表盘', icon: 'DataAnalysis', roles: ['teacher'], teacherView: ['backend'], component: loadView('teacher/GradeDashboard.vue') },
  { path: '/teacher/backend/grade-manage', title: '成绩管理', icon: 'Document', roles: ['teacher'], teacherView: ['backend'], component: loadView('teacher/GradeManage.vue') },
  { path: '/teacher/backend/homework-calendar', title: '作业日历', icon: 'Calendar', roles: ['teacher'], teacherView: ['backend'], component: loadView('teacher/HomeworkCalendar.vue') },
  { path: '/teacher/backend/my-log', title: '操作流水', icon: 'Tickets', roles: ['teacher'], teacherView: ['backend'], component: loadView('teacher/my-log.vue') },

  // 学校管理员也能用的跨模块
  { path: '/teacher/homework', title: '作业管理', icon: 'EditPen', roles: ['school_admin'], component: loadView('homework/views/HomeworkBoard.vue') },
  { path: '/teacher/grade-manage', title: '成绩管理', icon: 'Document', roles: ['school_admin'], component: loadView('teacher/GradeManage.vue') },
  {
    path: '/teacher/borrow',
    title: '物品借阅',
    icon: 'Goods',
    roles: ['school_admin'],
    component: () => import('@/modules/borrow/index').then(m => m.default.component()),
  },
]