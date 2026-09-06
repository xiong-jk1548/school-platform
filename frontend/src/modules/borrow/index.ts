import type { Role } from '@/types'

export default {
  name: 'borrow',
  label: '物品借阅',
  icon: 'Goods',
  roles: ['teacher', 'school_admin'] as Role[],
  path: '/teacher/borrow',
  component: () => import('./views/BorrowBoard.vue'),
  tablePrefix: 'borrow_',
}
