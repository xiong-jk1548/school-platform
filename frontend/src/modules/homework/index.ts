import type { Role } from '@/types'

export default {
  name: 'homework',
  label: '作业管理',
  icon: 'EditPen',
  roles: ['teacher', 'school_admin'] as Role[],
  path: '/teacher/homework',
  component: () => import('./views/HomeworkBoard.vue'),
  tablePrefix: 'homework_',
}
