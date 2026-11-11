import type { Role } from '@/types'

/**
 * 「作业管理」业务模块的插件入口定义。
 * 声明模块名称、菜单标题、图标、可访问角色与路由路径，供模块注册器动态挂载，
 * 页面组件按需懒加载，避免打进主包。
 */
export default {
  name: 'homework',
  label: '作业管理',
  icon: 'EditPen',
  roles: ['teacher', 'school_admin'] as Role[],
  path: '/teacher/homework',
  component: () => import('./views/HomeworkBoard.vue'),
  tablePrefix: 'homework_',
}
