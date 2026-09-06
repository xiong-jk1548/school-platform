/* eslint-disable @typescript-eslint/no-explicit-any */

export type Role = 'sys_admin' | 'school_admin' | 'teacher'

export interface School {
  id: string
  school_name: string
  name?: string
  school_code: string  // 系统自动生成，如 S001，用于跨学校学生学号去重（不显示）
  status: 'active' | 'inactive'
  address?: string
  contact_phone?: string
  grade_range?: string[]  // 教育局管理员设置，如 ['一年级', '二年级', ..., '六年级']
  create_time: string
  created_at?: string
}

export interface Profile {
  id: string
  email?: string
  phone?: string
  password: string
  real_name: string
  name?: string
  role: Role
  school_id?: string
  class_id?: string
  class_name?: string
  status: 'active' | 'inactive'
  create_time: string
  created_at?: string
}

export interface Class {
  id: string
  class_name: string
  name?: string
  school_id: string
  grade?: string
  homeroom_teacher_id?: string | null
  create_time: string
  created_at?: string
}

export interface Student {
  id: string
  student_name: string
  name?: string
  student_no?: string
  class_id: string
  school_id?: string
  gender?: 'male' | 'female' | 'other'
  birthday?: string
  total_score: number
  create_time: string
  created_at?: string
}

export interface ScoreLog {
  id: string
  student_id: string
  subject: string
  score_change: number
  score?: number
  score_type: 'daily' | 'exam' | 'homework'
  record_date: string
  operate_user_id?: string
  teacher_id?: string
  school_id?: string
  class_id?: string
  remark?: string
  create_time: string
  created_at?: string
}

export interface StudentAward {
  id: string
  student_id: string
  student_name?: string
  title: string
  level: string // 校级/市级/区级等
  award_type: string // 获奖/表扬/其他
  award_date: string
  description?: string
  school_id?: string
  class_id?: string
  operator_user_id?: string
  create_time: string
  created_at?: string
}

export interface StudentScore {
  id: string
  student_id: string
  student_name?: string
  subject: string
  subject_id?: string
  exam_name: string // 如：期中/期末/月考1
  exam_date: string
  score: number
  full_score: number
  school_id?: string
  class_id?: string
  operator_user_id?: string
  create_time: string
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

export interface HomeworkNote {
  id: string
  school_id: string
  class_id: string
  record_date: string
  subject_id: string
  subject_name?: string
  content: string
  create_time: string
  created_at?: string
}

export interface BorrowItem {
  id: string
  item_name: string
  name?: string
  type: string
  total_quantity: number
  available_quantity: number
  school_id?: string
  class_id?: string
  location?: string
  description?: string
  create_time: string
  created_at?: string
}

export interface BorrowRecord {
  id: string
  item_id: string
  student_id: string
  borrower_name?: string
  borrow_date: string
  expected_return_date?: string
  actual_return_date?: string
  status: 'borrowed' | 'returned' | 'overdue'
  qty?: number
  school_id?: string
  class_id?: string
  operator_user_id?: string
  remark?: string
  return_time?: string
  create_time: string
  created_at?: string
}

export interface Database {
  schools: School[]
  profiles: Profile[]
  classes: Class[]
  students: Student[]
  score_log: ScoreLog[]
  homework_subjects: HomeworkSubject[]
  homework_records: HomeworkRecord[]
  homework_notes: HomeworkNote[]
  borrow_items: BorrowItem[]
  borrow_records: BorrowRecord[]
  student_awards: StudentAward[]
  student_scores: StudentScore[]
}

const DB_KEY = 'MOCK_DB'
const SESSION_KEY = 'MOCK_SESSION'
const USE_MOCK_KEY = 'USE_MOCK'

function uuid(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0
    const v = c === 'x' ? r : (r & 0x3) | 0x8
    return v.toString(16)
  })
}

function nowISO(): string {
  return new Date().toISOString()
}

function getDB(): Database {
  const raw = localStorage.getItem(DB_KEY)
  if (!raw) return seedDB()
  return JSON.parse(raw)
}

function saveDB(db: Database): void {
  localStorage.setItem(DB_KEY, JSON.stringify(db))
}

function seedDB(): Database {
  const s1 = uuid()
  const s2 = uuid()
  const s3 = uuid()
  const c1 = uuid()
  const c2 = uuid()
  const c3 = uuid()
  const c4 = uuid()
  const today = nowISO()

  const schools: School[] = [
    { id: s1, school_name: '阳光小学', name: '阳光小学', school_code: 'SCH001', status: 'active', address: '北京市朝阳区阳光路1号', contact_phone: '010-8888-0001', grade_range: ['一年级', '二年级', '三年级', '四年级', '五年级', '六年级'], create_time: today, created_at: today },
    { id: s2, school_name: '希望中学', name: '希望中学', school_code: 'SCH002', status: 'active', address: '上海市浦东新区希望街88号', contact_phone: '021-6666-0002', grade_range: ['初一', '初二', '初三', '高一', '高二', '高三'], create_time: today, created_at: today },
    { id: s3, school_name: '梦想学园', name: '梦想学园', school_code: 'SCH003', status: 'inactive', address: '广州市天河区梦想路100号', contact_phone: '020-5555-0003', grade_range: ['一年级', '二年级', '三年级', '四年级', '五年级', '六年级'], create_time: today, created_at: today },
  ]

  const p1 = uuid()
  const p2 = uuid()
  const p3 = uuid()
  const p4 = uuid() // 阳光小学其他学科教师
  const p5 = uuid() // 希望中学初二三班班主任
  const p6 = uuid() // 希望中学高二一班班主任

  const profiles: Profile[] = [
    { id: p1, email: 'sys_admin@demo.com', phone: '13800000001', password: '123456', real_name: '超级管理员', name: '超级管理员', role: 'sys_admin', school_id: s1, status: 'active', create_time: today, created_at: today },
    { id: p2, email: 'school_admin@demo.com', phone: '13800000002', password: '123456', real_name: '阳光小学管理员', name: '阳光小学管理员', role: 'school_admin', school_id: s1, class_id: c1, class_name: '一年级一班', status: 'active', create_time: today, created_at: today },
    { id: p3, email: 'teacher@demo.com', phone: '13800000003', password: '123456', real_name: '王老师', name: '王老师', role: 'teacher', school_id: s1, class_id: c1, class_name: '一年级一班', status: 'active', create_time: today, created_at: today },
    { id: p4, email: 'teacher2@demo.com', phone: '13800000004', password: '123456', real_name: '张老师', name: '张老师', role: 'teacher', school_id: s1, status: 'active', create_time: today, created_at: today },
    { id: p5, email: 'teacher3@demo.com', phone: '13800000005', password: '123456', real_name: '李老师', name: '李老师', role: 'teacher', school_id: s2, class_id: c3, class_name: '初二三班', status: 'active', create_time: today, created_at: today },
    { id: p6, email: 'teacher4@demo.com', phone: '13800000006', password: '123456', real_name: '赵老师', name: '赵老师', role: 'teacher', school_id: s2, class_id: c4, class_name: '高二一班', status: 'active', create_time: today, created_at: today },
  ]

  // 给班级填 homeroom_teacher_id
  const classes: Class[] = [
    { id: c1, class_name: '一年级一班', name: '一年级一班', school_id: s1, grade: '一年级', homeroom_teacher_id: p3, create_time: today, created_at: today },
    { id: c2, class_name: '一年级二班', name: '一年级二班', school_id: s1, grade: '一年级', homeroom_teacher_id: null, create_time: today, created_at: today },
    { id: c3, class_name: '初二三班', name: '初二三班', school_id: s2, grade: '初二', homeroom_teacher_id: p5, create_time: today, created_at: today },
    { id: c4, class_name: '高二一班', name: '高二一班', school_id: s2, grade: '高二', homeroom_teacher_id: p6, create_time: today, created_at: today },
  ]

  const studentNames: Record<string, string[]> = {
    [c1]: ['张伟', '李娜', '王芳', '刘强', '陈静', '赵磊'],
    [c2]: ['杨洋', '黄涛', '周雪', '吴昊', '徐丽'],
    [c3]: ['孙明', '朱琳', '马超', '胡敏', '郭峰', '何燕', '高峰'],
    [c4]: ['林峰', '罗晓', '郑华', '梁斌', '谢芳'],
  }
  const genders: Record<string, ('male' | 'female')[]> = {
    [c1]: ['male', 'female', 'female', 'male', 'female', 'male'],
    [c2]: ['male', 'male', 'female', 'male', 'female'],
    [c3]: ['male', 'female', 'male', 'female', 'male', 'female', 'male'],
    [c4]: ['male', 'female', 'male', 'male', 'female'],
  }

  const students: Student[] = []
  for (const [clsId, names] of Object.entries(studentNames)) {
    const cls = classes.find((c) => c.id === clsId)
    names.forEach((n, i) => {
      students.push({
        id: uuid(),
        student_name: n,
        name: n,
        student_no: `2024${clsId.slice(-4)}${String(i + 1).padStart(2, '0')}`,
        class_id: clsId,
        school_id: cls?.school_id,
        gender: genders[clsId]?.[i] ?? 'male',
        birthday: `2015-${String(((i + 6) % 12) + 1).padStart(2, '0')}-${String(((i * 3) % 28) + 1).padStart(2, '0')}`,
        total_score: 100 + Math.floor(Math.random() * 200),
        create_time: today,
        created_at: today,
      })
    })
  }

  const subjectIds = {
    chinese: uuid(),
    math: uuid(),
    english: uuid(),
    physics: uuid(),
    chemistry: uuid(),
  }
  const subjects = ['语文', '数学', '英语', '物理', '化学']
  const homeworkSubjects: HomeworkSubject[] = [
    { id: subjectIds.chinese, subject_name: '语文', name: '语文', school_id: s1, sort_order: 1, create_time: today, created_at: today },
    { id: subjectIds.math, subject_name: '数学', name: '数学', school_id: s1, sort_order: 2, create_time: today, created_at: today },
    { id: subjectIds.english, subject_name: '英语', name: '英语', school_id: s1, sort_order: 3, create_time: today, created_at: today },
    { id: uuid(), subject_name: '科学', name: '科学', school_id: s1, sort_order: 4, create_time: today, created_at: today },
    { id: uuid(), subject_name: '语文', name: '语文', school_id: s2, sort_order: 1, create_time: today, created_at: today },
    { id: uuid(), subject_name: '数学', name: '数学', school_id: s2, sort_order: 2, create_time: today, created_at: today },
    { id: uuid(), subject_name: '物理', name: '物理', school_id: s2, sort_order: 3, create_time: today, created_at: today },
  ]

  const scoreLog: ScoreLog[] = []
  students.forEach((st) => {
    const subject = subjects[Math.floor(Math.random() * subjects.length)]
    scoreLog.push({
      id: uuid(),
      student_id: st.id,
      subject,
      score_change: Math.floor(Math.random() * 10) + 1,
      score: Math.floor(Math.random() * 10) + 1,
      score_type: 'daily',
      record_date: today,
      operate_user_id: p3,
      teacher_id: p3,
      school_id: st.school_id,
      class_id: st.class_id,
      remark: `${subject} 课堂表现优秀`,
      create_time: today,
      created_at: today,
    })
  })

  const homeworkRecords: HomeworkRecord[] = []
  const s1Subjects = homeworkSubjects.filter((s) => s.school_id === s1)
  const c1Students = students.filter((s) => s.class_id === c1)
  const todayDate = today.slice(0, 10)
  c1Students.forEach((st, si) => {
    s1Subjects.forEach((sub, sbi) => {
      const isDone = (si + sbi) % 3 !== 0
      homeworkRecords.push({
        id: uuid(),
        school_id: s1,
        class_id: c1,
        student_id: st.id,
        subject_id: sub.id,
        record_date: todayDate,
        is_done: isDone,
        update_user_id: p3,
        update_time: today,
        create_time: today,
        created_at: today,
      })
    })
  })

  // 作业备注 seed
  const homeworkNotes: HomeworkNote[] = []
  const noteTemplates: Record<string, string> = {
    '语文': '抄写第5课生词 2 遍，背诵古诗两首',
    '数学': '口算练习册 P32-P35，应用题 3 道',
    '英语': 'Unit 4 单词抄写 + 听力练习',
  }
  s1Subjects.forEach((sub) => {
    const content = noteTemplates[sub.subject_name] || '完成课本对应章节练习'
    homeworkNotes.push({
      id: uuid(),
      school_id: s1,
      class_id: c1,
      record_date: todayDate,
      subject_id: sub.id,
      subject_name: sub.subject_name,
      content,
      create_time: today,
      created_at: today,
    })
  })

  const studentAwards: StudentAward[] = []
  c1Students.slice(0, 3).forEach((st, i) => {
    const titles = ['三好学生', '数学竞赛一等奖', '运动会跳远冠军']
    const levels = ['校级', '区级', '校级']
    studentAwards.push({
      id: uuid(),
      student_id: st.id,
      student_name: st.student_name,
      title: titles[i],
      level: levels[i],
      award_type: '获奖',
      award_date: today,
      description: '',
      school_id: s1,
      class_id: c1,
      operator_user_id: p3,
      create_time: today,
      created_at: today,
    })
  })

  // ===== 学生成绩种子数据 =====
  const subjectsArr = ['语文', '数学', '英语']
  const examNames = ['第一次月考', '期中考试', '第二次月考']
  const examDates = [
    new Date(Date.now() - 60 * 86400000).toISOString(),
    new Date(Date.now() - 30 * 86400000).toISOString(),
    new Date(Date.now() - 10 * 86400000).toISOString(),
  ]
  const studentScores: StudentScore[] = []
  c1Students.forEach((st) => {
    examNames.forEach((examName, ei) => {
      subjectsArr.forEach((subject) => {
        const baseScore = 60 + Math.floor(Math.random() * 40)
        studentScores.push({
          id: uuid(),
          student_id: st.id,
          student_name: st.student_name,
          subject,
          exam_name: examName,
          exam_date: examDates[ei],
          score: Math.min(100, Math.max(0, baseScore + (Math.floor(Math.random() * 20) - 10))),
          full_score: 100,
          school_id: s1,
          class_id: c1,
          operator_user_id: p3,
          create_time: examDates[ei],
          created_at: examDates[ei],
        })
      })
    })
  })

  const borrowItems: BorrowItem[] = [
    { id: uuid(), item_name: '足球', name: '足球', type: '体育器材', total_quantity: 10, available_quantity: 8, school_id: s1, class_id: c1, location: '器材室A架', description: '标准5号足球', create_time: today, created_at: today },
    { id: uuid(), item_name: '羽毛球拍', name: '羽毛球拍', type: '体育器材', total_quantity: 15, available_quantity: 12, school_id: s1, class_id: c1, location: '器材室A架', description: '铝合金材质羽毛球拍', create_time: today, created_at: today },
    { id: uuid(), item_name: '跳绳', name: '跳绳', type: '体育器材', total_quantity: 30, available_quantity: 25, school_id: s1, class_id: c1, location: '器材室B架', description: '标准长度跳绳', create_time: today, created_at: today },
    { id: uuid(), item_name: '篮球', name: '篮球', type: '体育器材', total_quantity: 8, available_quantity: 6, school_id: s1, class_id: c1, location: '器材室A架', create_time: today, created_at: today },
    { id: uuid(), item_name: '哑铃套装', name: '哑铃套装', type: '健身器材', total_quantity: 5, available_quantity: 5, school_id: s1, class_id: c1, location: '器材室C架', description: '可调节重量', create_time: today, created_at: today },
  ]

  const borrowRecords: BorrowRecord[] = []
  const activeItems = borrowItems.slice(0, 2)
  activeItems.forEach((item, i) => {
    const st = students[i]
    const borrowDate = new Date(Date.now() - (i + 1) * 86400000).toISOString()
    borrowRecords.push({
      id: uuid(),
      item_id: item.id,
      student_id: st.id,
      borrower_name: st.student_name,
      borrow_date: borrowDate,
      expected_return_date: new Date(Date.now() + 3 * 86400000).toISOString(),
      status: 'borrowed',
      qty: 2,
      school_id: s1,
      class_id: c1,
      remark: '课外活动借用',
      create_time: borrowDate,
      created_at: borrowDate,
    })
  })

  const db: Database = {
    schools,
    profiles,
    classes,
    students,
    score_log: scoreLog,
    homework_subjects: homeworkSubjects,
    homework_records: homeworkRecords,
    homework_notes: homeworkNotes,
    borrow_items: borrowItems,
    borrow_records: borrowRecords,
    student_awards: studentAwards,
    student_scores: studentScores,
  }
  saveDB(db)
  return db
}

export function resetMockData(): void {
  localStorage.removeItem(DB_KEY)
  localStorage.removeItem(SESSION_KEY)
  seedDB()
}

function getSession(): MockSession | null {
  const raw = localStorage.getItem(SESSION_KEY)
  if (!raw) return null
  return JSON.parse(raw)
}

function saveSession(s: MockSession | null): void {
  if (s) localStorage.setItem(SESSION_KEY, JSON.stringify(s))
  else localStorage.removeItem(SESSION_KEY)
}

export function useMockMode(): boolean {
  return import.meta.env.DEV && !import.meta.env.VITE_USE_REAL_SUPABASE
    ? true
    : localStorage.getItem(USE_MOCK_KEY) === 'true'
}

interface MockUser {
  id: string
  email?: string
  user_metadata: {
    role: Role
    name: string
    phone?: string
    school_id?: string
    class_id?: string
    class_name?: string
  }
  aud: string
  created_at: string
}

interface MockSession {
  access_token: string
  token_type: string
  expires_in: number
  user: MockUser
}

function profileToUser(p: Profile): MockUser {
  return {
    id: p.id,
    email: p.email,
    user_metadata: {
      role: p.role,
      name: p.real_name,
      phone: p.phone,
      school_id: p.school_id,
      class_id: p.class_id,
      class_name: p.class_name,
    },
    aud: 'authenticated',
    created_at: p.create_time,
  }
}

function currentProfile(): Profile | null {
  const sess = getSession()
  if (!sess) return null
  const db = getDB()
  const profile = db.profiles.find((p) => p.id === sess.user.id) ?? null
  if (!profile) return null
  const override = localStorage.getItem('MOCK_ROLE_OVERRIDE') as Role | null
  if (override && ['sys_admin', 'school_admin', 'teacher'].includes(override)) {
    return { ...profile, role: override }
  }
  return profile
}

/**
 * 教师当前选中的班级（用于前端访问）。存在 localStorage['MOCK_SELECTED_CLASS']，
 * 由 MainLayout 里的班级下拉切换器写入。如果未设置则 fallback 到 profile 里绑定的 class_id。
 */
export function getSelectedClassId(): string | null {
  const stored = localStorage.getItem('MOCK_SELECTED_CLASS')
  if (stored) return stored
  const profile = currentProfile()
  return profile?.class_id ?? null
}

function applyRoleOverride(user: MockUser): MockUser {
  const override = localStorage.getItem('MOCK_ROLE_OVERRIDE') as Role | null
  if (override && ['sys_admin', 'school_admin', 'teacher'].includes(override)) {
    return {
      ...user,
      user_metadata: { ...user.user_metadata, role: override },
    }
  }
  return user
}

function rlsFilter<T extends Record<string, any>>(table: string, rows: T[], action: 'select' | 'insert' | 'update' | 'delete'): T[] {
  const profile = currentProfile()
  if (!profile) {
    if (action === 'select') return rows
    return rows
  }
  if (profile.role === 'sys_admin') return rows
  switch (table) {
    case 'schools':
      if (profile.role === 'school_admin') return rows.filter((r) => r.id === profile.school_id)
      return []
    case 'profiles':
    case 'classes':
    case 'students':
    case 'score_log':
    case 'homework_subjects':
    case 'homework_records':
    case 'homework_notes':
    case 'borrow_records':
    case 'student_awards':
    case 'student_scores': {
      if (profile.role === 'school_admin') {
        const db = getDB()
        const classIds = db.classes.filter((c) => c.school_id === profile.school_id).map((c) => c.id)
        return rows.filter((r) => {
          if (table === 'students' || table === 'classes') return classIds.includes(r.class_id ?? r.id) || r.school_id === profile.school_id
          if (table === 'homework_subjects') return r.school_id === profile.school_id
          if (table === 'homework_records' || table === 'homework_notes') return r.school_id === profile.school_id && classIds.includes(r.class_id)
          if (table === 'score_log' || table === 'borrow_records' || table === 'student_awards' || table === 'student_scores') {
            const st = db.students.find((s) => s.id === r.student_id)
            return st ? classIds.includes(st.class_id) : false
          }
          if (table === 'profiles') return r.school_id === profile.school_id || r.id === profile.id
          return false
        })
      }
      if (profile.role === 'teacher') {
        const db = getDB()
        // 教师可以查看自己学校任何班级的数据，但通过 MainLayout 的班级切换器决定"当前查看哪一个班"
        // 后端（成绩/仪表盘）是否允许写入由 MainLayout 的菜单显隐控制
        const selectedClassId = getSelectedClassId() ?? profile.class_id
        // classes 表：让学校的所有班级都可见（这样教师可以切班级）
        const schoolClassIds = db.classes.filter((c) => c.school_id === profile.school_id).map((c) => c.id)
        return rows.filter((r) => {
          if (table === 'classes') return schoolClassIds.includes(r.id)
          if (table === 'homework_subjects') return r.school_id === profile.school_id
          if (table === 'students') return r.class_id === selectedClassId
          if (table === 'homework_records' || table === 'homework_notes') return r.class_id === selectedClassId
          if (table === 'score_log' || table === 'borrow_records' || table === 'student_awards' || table === 'student_scores') {
            const st = db.students.find((s) => s.id === r.student_id)
            return st ? st.class_id === selectedClassId : false
          }
          return false
        })
      }
      return rows
    }
    case 'borrow_items': {
      if (profile.role === 'school_admin') {
        return rows.filter((r) => r.school_id === profile.school_id)
      }
      if (profile.role === 'teacher') {
        return rows.filter((r) => r.class_id === profile.class_id)
      }
      return rows
    }
    default:
      return rows
  }
}

type FilterValue = string | number | boolean | null
type RlsAction = 'select' | 'insert' | 'update' | 'delete'

interface FilterChain {
  eq: (col: string, val: FilterValue) => FilterChain
  neq: (col: string, val: FilterValue) => FilterChain
  gt: (col: string, val: number) => FilterChain
  gte: (col: string, val: number) => FilterChain
  lt: (col: string, val: number) => FilterChain
  lte: (col: string, val: number) => FilterChain
  in: (col: string, vals: FilterValue[]) => FilterChain
  like: (col: string, pattern: string) => FilterChain
  ilike: (col: string, pattern: string) => FilterChain
  order: (col: string, opts?: { ascending?: boolean }) => FilterChain
  limit: (n: number) => FilterChain
  select: (columns?: string) => Promise<{ data: any[]; error: null }>
  maybeSingle: () => Promise<{ data: any | null; error: null }>
  single: () => Promise<{ data: any; error: null }>
}

type QueryResult = { data: any[]; error: null; count?: number }

class QueryChain implements FilterChain {
  private filters: ((row: any) => boolean)[] = []
  private orderCol: string | null = null
  private orderAsc: boolean = true
  private limitN: number | null = null
  private tableName: string
  private action: RlsAction
  private updateData?: Record<string, any>
  private selectOpts?: { count?: 'exact' | 'planned'; head?: boolean }

  constructor(tableName: string, action: RlsAction, updateData?: Record<string, any>, selectOpts?: { count?: 'exact' | 'planned'; head?: boolean }) {
    this.tableName = tableName
    this.action = action
    this.updateData = updateData
    this.selectOpts = selectOpts
  }

  eq(col: string, val: FilterValue): this { this.filters.push((r) => r[col] === val); return this }
  neq(col: string, val: FilterValue): this { this.filters.push((r) => r[col] !== val); return this }
  gt(col: string, val: number): this { this.filters.push((r) => Number(r[col]) > val); return this }
  gte(col: string, val: number): this { this.filters.push((r) => Number(r[col]) >= val); return this }
  lt(col: string, val: number): this { this.filters.push((r) => Number(r[col]) < val); return this }
  lte(col: string, val: number): this { this.filters.push((r) => Number(r[col]) <= val); return this }
  in(col: string, vals: FilterValue[]): this { this.filters.push((r) => vals.includes(r[col])); return this }
  like(col: string, pattern: string): this {
    const p = pattern.replace(/%/g, '')
    this.filters.push((r) => String(r[col] ?? '').includes(p)); return this
  }
  ilike(col: string, pattern: string): this {
    const p = pattern.replace(/%/g, '').toLowerCase()
    this.filters.push((r) => String(r[col] ?? '').toLowerCase().includes(p)); return this
  }
  order(col: string, opts?: { ascending?: boolean }): this {
    this.orderCol = col
    this.orderAsc = opts?.ascending !== false; return this
  }
  limit(n: number): this { this.limitN = n; return this }

  select(_columns?: string, opts?: { count?: 'exact' | 'planned'; head?: boolean }): Promise<QueryResult> {
    this.selectOpts = opts
    return Promise.resolve(this._execute(opts))
  }

  maybeSingle(): Promise<{ data: any | null; error: null }> {
    return Promise.resolve(this._execute()).then((r) => ({
      data: r.data.length > 0 ? r.data[0] : null,
      error: null,
    }))
  }

  single(): Promise<{ data: any; error: null }> {
    return Promise.resolve(this._execute()).then((r) => ({
      data: r.data[0] ?? null,
      error: null,
    }))
  }

  private _applyFilters(rows: any[]): any[] {
    let result = rows.filter((r) => this.filters.every((f) => f(r)))
    if (this.orderCol) {
      result = [...result].sort((a, b) => {
        const av = a[this.orderCol!]
        const bv = b[this.orderCol!]
        if (av < bv) return this.orderAsc ? -1 : 1
        if (av > bv) return this.orderAsc ? 1 : -1
        return 0
      })
    }
    if (this.limitN !== null) result = result.slice(0, this.limitN!)
    return result
  }

  private _execute(selectOpts?: { count?: 'exact' | 'planned'; head?: boolean }): QueryResult {
    const db = getDB()
    const key = this.tableName as keyof Database
    const all: any[] = [...(db[key] as any[])]

    if (this.action === 'select') {
      const rlsRows = rlsFilter(this.tableName, all, 'select')
      const filtered = this._applyFilters(rlsRows)
      // head + count 模式：只返回 count，不返回 data 内容
      if (selectOpts?.count && selectOpts?.head) {
        return { data: [], error: null, count: filtered.length }
      }
      // count 模式：data 正常返回，附带 count
      if (selectOpts?.count) {
        return { data: filtered, error: null, count: filtered.length }
      }
      return { data: filtered, error: null }
    }

    if (this.action === 'update') {
      const toUpdate = this._applyFilters(all)
      if (this.tableName === 'borrow_records') {
        for (const r of toUpdate) {
          const idx = (db[key] as any[]).findIndex((x) => x.id === r.id)
          if (idx !== -1) {
            const oldRow = (db[key] as any[])[idx]
            const oldStatus = oldRow.status
            const oldQty = Number(oldRow.qty ?? 1)
            const merged = { ...oldRow, ...this.updateData }
            ;(db[key] as any[])[idx] = merged
            if (oldStatus === 'borrowed' && merged.status === 'returned') {
              const item = db.borrow_items.find((it) => it.id === oldRow.item_id)
              if (item) item.available_quantity = (item.available_quantity ?? 0) + oldQty
            }
            if (oldStatus === 'returned' && merged.status === 'borrowed') {
              const item = db.borrow_items.find((it) => it.id === oldRow.item_id)
              if (item) item.available_quantity = Math.max(0, (item.available_quantity ?? 0) - Number(merged.qty ?? oldQty))
            }
          }
        }
      } else {
        for (const r of toUpdate) {
          const idx = (db[key] as any[]).findIndex((x) => x.id === r.id)
          if (idx !== -1) {
            ;(db[key] as any[])[idx] = { ...(db[key] as any[])[idx], ...this.updateData }
          }
        }
      }
      saveDB(db)
      return { data: toUpdate, error: null }
    }

    if (this.action === 'delete') {
      const toDelete = this._applyFilters(all)
      const idsToRemove = new Set(toDelete.map((r) => r.id))
      ;(db[key] as any[]) = (db[key] as any[]).filter((x) => !idsToRemove.has(x.id))
      saveDB(db)
      return { data: toDelete, error: null }
    }

    return { data: [], error: null }
  }

  then<TResult1 = QueryResult, TResult2 = never>(
    onfulfilled?: ((value: QueryResult) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: any) => TResult2 | PromiseLike<TResult2>) | null
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve(this._execute(this.selectOpts)).then(onfulfilled, onrejected)
  }
}

function fromTable(tableName: string) {
  return {
    select(_columns?: string, opts?: { count?: 'exact' | 'planned'; head?: boolean }) {
      return new QueryChain(tableName, 'select', undefined, opts)
    },
    insert(rows: any | any[]) {
      const rowArr = Array.isArray(rows) ? rows : [rows]
      rowArr.forEach((r: any) => {
        if (!r.id) r.id = uuid()
        if (!r.create_time && !r.created_at) {
          const t = nowISO()
          r.create_time = t
          r.created_at = t
        }
      })
      const db = getDB()
      const key = tableName as keyof Database
      if (key in db) {
        ;(db[key] as any[]).push(...rowArr)
      }
      if (tableName === 'borrow_records') {
        for (const rec of rowArr) {
          if (rec.status === 'borrowed' && rec.item_id) {
            const item = db.borrow_items.find((it) => it.id === rec.item_id)
            if (item) item.available_quantity = Math.max(0, (item.available_quantity ?? 0) - Number(rec.qty ?? 1))
          }
        }
      }
      saveDB(db)
      return {
        select: () => Promise.resolve({ data: rowArr, error: null }),
        then: (cb: any) => Promise.resolve({ data: rowArr, error: null }).then(cb),
      }
    },
    update(data: Record<string, any>) {
      return new QueryChain(tableName, 'update', data)
    },
    delete() {
      return new QueryChain(tableName, 'delete')
    },
  }
}

const mockAuth = {
  signInWithPassword: async ({ email, password }: { email: string; password: string }): Promise<{ data: { user: MockUser | null; session: MockSession | null }; error: any }> => {
    await new Promise((r) => setTimeout(r, 300))
    const db = getDB()
    const profile = db.profiles.find((p) => (p.phone === email || p.email === email) && p.password === password)
    if (!profile) {
      return { data: { user: null, session: null }, error: { message: '账号或密码错误' } }
    }
    if (profile.status !== 'active') {
      return { data: { user: null, session: null }, error: { message: '账号已被禁用' } }
    }
    const user = profileToUser(profile)
    localStorage.removeItem('MOCK_ROLE_OVERRIDE')
    const session: MockSession = {
      access_token: 'mock-token-' + uuid(),
      token_type: 'bearer',
      expires_in: 3600,
      user,
    }
    saveSession(session)
    return { data: { user, session }, error: null }
  },
  signOut: async (): Promise<{ error: any }> => {
    await new Promise((r) => setTimeout(r, 100))
    saveSession(null)
    return { error: null }
  },
  getSession: async (): Promise<{ data: { session: MockSession | null }; error: any }> => {
    const s = getSession()
    if (!s) return { data: { session: null }, error: null }
    const overriddenUser = applyRoleOverride(s.user)
    return {
      data: { session: { ...s, user: overriddenUser } },
      error: null,
    }
  },
  getUser: async (): Promise<{ data: { user: MockUser | null }; error: any }> => {
    const s = getSession()
    if (!s) return { data: { user: null }, error: null }
    return { data: { user: applyRoleOverride(s.user) }, error: null }
  },
  onAuthStateChange: (_callback: (event: string, session: MockSession | null) => void) => {
    return { data: { subscription: { unsubscribe: () => {} } } }
  },
}

function rpc(name: string, params: Record<string, any>): Promise<{ data: any; error: any }> {
  return Promise.resolve().then(() => {
    if (name === 'fn_change_student_score') {
      const { p_student_id, p_score_change, p_remark } = params
      const db = getDB()
      const student = db.students.find((s) => s.id === p_student_id)
      if (!student) return { data: null, error: { message: '学生不存在' } }
      const change = Number(p_score_change)
      if (isNaN(change)) return { data: null, error: { message: '积分变化值无效' } }
      student.total_score = (student.total_score ?? 0) + change
      const session = getSession()
      const log: ScoreLog = {
        id: uuid(),
        student_id: p_student_id,
        subject: '积分调整',
        score_change: change,
        score: change,
        score_type: 'daily',
        record_date: nowISO(),
        operate_user_id: session?.user.id,
        teacher_id: session?.user.id,
        school_id: student.school_id,
        class_id: student.class_id,
        remark: p_remark ?? '',
        create_time: nowISO(),
        created_at: nowISO(),
      }
      db.score_log.push(log)
      saveDB(db)
      return { data: { ok: true }, error: null }
    }
    return { data: null, error: { message: `未知 RPC: ${name}` } }
  })
}

export const mockSupabase = {
  auth: mockAuth,
  from: fromTable,
  rpc,
}
