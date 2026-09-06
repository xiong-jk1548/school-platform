export type Role = 'sys_admin' | 'school_admin' | 'teacher'

export interface UserState {
  userId: string | null
  email: string | null
  realName: string | null
  role: Role | null
  schoolId: string | null
  classId: string | null
  className: string | null
}

export interface School {
  id: string
  name: string
  address?: string
  contact_phone?: string
  created_at?: string
}

export interface Class {
  id: string
  name: string
  school_id: string
  grade?: string
  created_at?: string
}

export interface Student {
  id: string
  name: string
  student_no?: string
  class_id: string
  gender?: 'male' | 'female' | 'other'
  birthday?: string
  created_at?: string
}

export interface ScoreLog {
  id: string
  student_id: string
  subject: string
  score: number
  score_type: 'daily' | 'exam' | 'homework'
  record_date: string
  teacher_id?: string
  remark?: string
  created_at?: string
}

export interface HomeworkSubject {
  id: string
  subject_name: string
  name?: string
  school_id: string
  sort_order: number
  create_time: string
  created_at?: string
}

export interface HomeworkRecord {
  id: string
  school_id: string
  class_id: string
  student_id: string
  subject_id: string
  record_date: string
  is_done: boolean
  update_user_id?: string
  update_time?: string
  create_time: string
  created_at?: string
}

export interface BorrowItem {
  id: string
  name: string
  type: string
  total_quantity: number
  available_quantity: number
  description?: string
  created_at?: string
}

export interface BorrowRecord {
  id: string
  item_id: string
  student_id: string
  borrower_name: string
  borrow_date: string
  expected_return_date: string
  actual_return_date?: string
  status: 'borrowed' | 'returned' | 'overdue'
  remark?: string
  created_at?: string
}
