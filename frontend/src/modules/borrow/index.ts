import type { Role } from '@/types'

/**
 * 「物品借阅」业务模块的插件入口定义。
 * 声明模块名称、菜单标题、图标、可访问角色与路由路径，供模块注册器动态挂载，
 * 页面组件按需懒加载，避免打进主包。
 */
export default {
  name: 'borrow',
  label: '物品借阅',
  icon: 'Goods',
  roles: ['teacher', 'school_admin'] as Role[],
  path: '/teacher/borrow',
  component: () => import('./views/BorrowBoard.vue'),
  tablePrefix: 'borrow_',
}
