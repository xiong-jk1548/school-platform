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

/** 本地 Mock 数据库在 localStorage 中的存储键名 */
const DB_KEY = 'MOCK_DB'
/** 登录会话在 localStorage 中的存储键名 */
const SESSION_KEY = 'MOCK_SESSION'
/** 「是否强制使用 Mock 后端」开关在 localStorage 中的存储键名 */
const USE_MOCK_KEY = 'USE_MOCK'

/**
 * 生成一个符合 UUID v4 格式的随机字符串，供 Mock 数据的主键使用。
 * @returns 形如 xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx 的随机 UUID
 */
function uuid(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (placeholder) => {
    const randomInt = (Math.random() * 16) | 0
    const hexDigit = placeholder === 'x' ? randomInt : (randomInt & 0x3) | 0x8
    return hexDigit.toString(16)
  })
}

/**
 * 取当前时间的 ISO 字符串，统一用于 Mock 数据的各类时间字段。
 * @returns ISO 8601 格式的当前时间字符串
 */
function nowISO(): string {
  return new Date().toISOString()
}

/**
 * 读取本地 Mock 数据库：首次访问（localStorage 中无数据）时自动写入一份种子数据。
 * @returns 完整的 Mock 数据库对象
 */
function getDB(): Database {
  const storedJson = localStorage.getItem(DB_KEY)
  if (!storedJson) return seedDB()
  return JSON.parse(storedJson)
}

/**
 * 将内存中的 Mock 数据库整体序列化写回 localStorage。
 * @param db 待持久化的数据库对象
 * @returns 无返回值（副作用：写入 localStorage）
 */
function saveDB(db: Database): void {
  localStorage.setItem(DB_KEY, JSON.stringify(db))
}

/**
 * 构造一份演示用的种子数据（学校、账号、班级、学生、作业、借阅等）。
 * 仅在 localStorage 中没有 Mock 数据时调用，生成后立即落盘。
 * @returns 新生成的 Mock 数据库对象
 */
function seedDB(): Database {
  const sunshineSchoolId = uuid()
  const hopeSchoolId = uuid()
  const dreamSchoolId = uuid()
  const classOneOneId = uuid()
  const classOneTwoId = uuid()
  const classTwoThreeId = uuid()
  const classTwoOneId = uuid()
  const today = nowISO()

  const schools: School[] = [
    { id: sunshineSchoolId, school_name: '阳光小学', name: '阳光小学', school_code: 'SCH001', status: 'active', address: '北京市朝阳区阳光路1号', contact_phone: '010-8888-0001', grade_range: ['一年级', '二年级', '三年级', '四年级', '五年级', '六年级'], create_time: today, created_at: today },
    { id: hopeSchoolId, school_name: '希望中学', name: '希望中学', school_code: 'SCH002', status: 'active', address: '上海市浦东新区希望街88号', contact_phone: '021-6666-0002', grade_range: ['初一', '初二', '初三', '高一', '高二', '高三'], create_time: today, created_at: today },
    { id: dreamSchoolId, school_name: '梦想学园', name: '梦想学园', school_code: 'SCH003', status: 'inactive', address: '广州市天河区梦想路100号', contact_phone: '020-5555-0003', grade_range: ['一年级', '二年级', '三年级', '四年级', '五年级', '六年级'], create_time: today, created_at: today },
  ]

  const sysAdminProfileId = uuid()
  const schoolAdminProfileId = uuid()
  const teacherWangProfileId = uuid()
  const teacherZhangProfileId = uuid() // 阳光小学其他学科教师
  const teacherLiProfileId = uuid() // 希望中学初二三班班主任
  const teacherZhaoProfileId = uuid() // 希望中学高二一班班主任

  const profiles: Profile[] = [
    { id: sysAdminProfileId, email: 'sys_admin@demo.com', phone: '13800000001', password: '123456', real_name: '超级管理员', name: '超级管理员', role: 'sys_admin', school_id: sunshineSchoolId, status: 'active', create_time: today, created_at: today },
    { id: schoolAdminProfileId, email: 'school_admin@demo.com', phone: '13800000002', password: '123456', real_name: '阳光小学管理员', name: '阳光小学管理员', role: 'school_admin', school_id: sunshineSchoolId, class_id: classOneOneId, class_name: '一年级一班', status: 'active', create_time: today, created_at: today },
    { id: teacherWangProfileId, email: 'teacher@demo.com', phone: '13800000003', password: '123456', real_name: '王老师', name: '王老师', role: 'teacher', school_id: sunshineSchoolId, class_id: classOneOneId, class_name: '一年级一班', status: 'active', create_time: today, created_at: today },
    { id: teacherZhangProfileId, email: 'teacher2@demo.com', phone: '13800000004', password: '123456', real_name: '张老师', name: '张老师', role: 'teacher', school_id: sunshineSchoolId, status: 'active', create_time: today, created_at: today },
    { id: teacherLiProfileId, email: 'teacher3@demo.com', phone: '13800000005', password: '123456', real_name: '李老师', name: '李老师', role: 'teacher', school_id: hopeSchoolId, class_id: classTwoThreeId, class_name: '初二三班', status: 'active', create_time: today, created_at: today },
    { id: teacherZhaoProfileId, email: 'teacher4@demo.com', phone: '13800000006', password: '123456', real_name: '赵老师', name: '赵老师', role: 'teacher', school_id: hopeSchoolId, class_id: classTwoOneId, class_name: '高二一班', status: 'active', create_time: today, created_at: today },
  ]

  // 给班级填 homeroom_teacher_id
  const classes: Class[] = [
    { id: classOneOneId, class_name: '一年级一班', name: '一年级一班', school_id: sunshineSchoolId, grade: '一年级', homeroom_teacher_id: teacherWangProfileId, create_time: today, created_at: today },
    { id: classOneTwoId, class_name: '一年级二班', name: '一年级二班', school_id: sunshineSchoolId, grade: '一年级', homeroom_teacher_id: null, create_time: today, created_at: today },
    { id: classTwoThreeId, class_name: '初二三班', name: '初二三班', school_id: hopeSchoolId, grade: '初二', homeroom_teacher_id: teacherLiProfileId, create_time: today, created_at: today },
    { id: classTwoOneId, class_name: '高二一班', name: '高二一班', school_id: hopeSchoolId, grade: '高二', homeroom_teacher_id: teacherZhaoProfileId, create_time: today, created_at: today },
  ]

  const studentNameByClass: Record<string, string[]> = {
    [classOneOneId]: ['张伟', '李娜', '王芳', '刘强', '陈静', '赵磊'],
    [classOneTwoId]: ['杨洋', '黄涛', '周雪', '吴昊', '徐丽'],
    [classTwoThreeId]: ['孙明', '朱琳', '马超', '胡敏', '郭峰', '何燕', '高峰'],
    [classTwoOneId]: ['林峰', '罗晓', '郑华', '梁斌', '谢芳'],
  }
  const classGenders: Record<string, ('male' | 'female')[]> = {
    [classOneOneId]: ['male', 'female', 'female', 'male', 'female', 'male'],
    [classOneTwoId]: ['male', 'male', 'female', 'male', 'female'],
    [classTwoThreeId]: ['male', 'female', 'male', 'female', 'male', 'female', 'male'],
    [classTwoOneId]: ['male', 'female', 'male', 'male', 'female'],
  }

  const students: Student[] = []
  for (const [classRowId, classStudentNames] of Object.entries(studentNameByClass)) {
    const classRow = classes.find((classItem) => classItem.id === classRowId)
    classStudentNames.forEach((studentName, studentIndex) => {
      students.push({
        id: uuid(),
        student_name: studentName,
        name: studentName,
        student_no: `2024${classRowId.slice(-4)}${String(studentIndex + 1).padStart(2, '0')}`,
        class_id: classRowId,
        school_id: classRow?.school_id,
        gender: classGenders[classRowId]?.[studentIndex] ?? 'male',
        birthday: `2015-${String(((studentIndex + 6) % 12) + 1).padStart(2, '0')}-${String(((studentIndex * 3) % 28) + 1).padStart(2, '0')}`,
        total_score: 100 + Math.floor(Math.random() * 200),
        create_time: today,
        created_at: today,
      })
    })
  }

  const subjectIdMap = {
    chinese: uuid(),
    math: uuid(),
    english: uuid(),
    physics: uuid(),
    chemistry: uuid(),
  }
  const subjectNameList = ['语文', '数学', '英语', '物理', '化学']
  const homeworkSubjects: HomeworkSubject[] = [
    { id: subjectIdMap.chinese, subject_name: '语文', name: '语文', school_id: sunshineSchoolId, sort_order: 1, create_time: today, created_at: today },
    { id: subjectIdMap.math, subject_name: '数学', name: '数学', school_id: sunshineSchoolId, sort_order: 2, create_time: today, created_at: today },
    { id: subjectIdMap.english, subject_name: '英语', name: '英语', school_id: sunshineSchoolId, sort_order: 3, create_time: today, created_at: today },
    { id: uuid(), subject_name: '科学', name: '科学', school_id: sunshineSchoolId, sort_order: 4, create_time: today, created_at: today },
    { id: uuid(), subject_name: '语文', name: '语文', school_id: hopeSchoolId, sort_order: 1, create_time: today, created_at: today },
    { id: uuid(), subject_name: '数学', name: '数学', school_id: hopeSchoolId, sort_order: 2, create_time: today, created_at: today },
    { id: uuid(), subject_name: '物理', name: '物理', school_id: hopeSchoolId, sort_order: 3, create_time: today, created_at: today },
  ]

  const scoreLogEntries: ScoreLog[] = []
  students.forEach((studentRow) => {
    const subjectName = subjectNameList[Math.floor(Math.random() * subjectNameList.length)]
    scoreLogEntries.push({
      id: uuid(),
      student_id: studentRow.id,
      subject: subjectName,
      score_change: Math.floor(Math.random() * 10) + 1,
      score: Math.floor(Math.random() * 10) + 1,
      score_type: 'daily',
      record_date: today,
      operate_user_id: teacherWangProfileId,
      teacher_id: teacherWangProfileId,
      school_id: studentRow.school_id,
      class_id: studentRow.class_id,
      remark: `${subjectName} 课堂表现优秀`,
      create_time: today,
      created_at: today,
    })
  })

  const homeworkRecords: HomeworkRecord[] = []
  const sunshineSubjectList = homeworkSubjects.filter((subjectRow) => subjectRow.school_id === sunshineSchoolId)
  const classOneOneStudentList = students.filter((studentRow) => studentRow.class_id === classOneOneId)
  const todayDate = today.slice(0, 10)
  classOneOneStudentList.forEach((studentRow, studentIndex) => {
    sunshineSubjectList.forEach((subjectRow, subjectIndex) => {
      const isDone = (studentIndex + subjectIndex) % 3 !== 0
      homeworkRecords.push({
        id: uuid(),
        school_id: sunshineSchoolId,
        class_id: classOneOneId,
        student_id: studentRow.id,
        subject_id: subjectRow.id,
        record_date: todayDate,
        is_done: isDone,
        update_user_id: teacherWangProfileId,
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
  sunshineSubjectList.forEach((subjectRow) => {
    const noteContent = noteTemplates[subjectRow.subject_name] || '完成课本对应章节练习'
    homeworkNotes.push({
      id: uuid(),
      school_id: sunshineSchoolId,
      class_id: classOneOneId,
      record_date: todayDate,
      subject_id: subjectRow.id,
      subject_name: subjectRow.subject_name,
      content: noteContent,
      create_time: today,
      created_at: today,
    })
  })

  const studentAwards: StudentAward[] = []
  classOneOneStudentList.slice(0, 3).forEach((studentRow, studentIndex) => {
    const awardTitles = ['三好学生', '数学竞赛一等奖', '运动会跳远冠军']
    const awardLevels = ['校级', '区级', '校级']
    studentAwards.push({
      id: uuid(),
      student_id: studentRow.id,
      student_name: studentRow.student_name,
      title: awardTitles[studentIndex],
      level: awardLevels[studentIndex],
      award_type: '获奖',
      award_date: today,
      description: '',
      school_id: sunshineSchoolId,
      class_id: classOneOneId,
      operator_user_id: teacherWangProfileId,
      create_time: today,
      created_at: today,
    })
  })

  // ===== 学生成绩种子数据 =====
  const scoreSubjectNames = ['语文', '数学', '英语']
  const examNames = ['第一次月考', '期中考试', '第二次月考']
  const examDates = [
    new Date(Date.now() - 60 * 86400000).toISOString(),
    new Date(Date.now() - 30 * 86400000).toISOString(),
    new Date(Date.now() - 10 * 86400000).toISOString(),
  ]
  const studentScores: StudentScore[] = []
  classOneOneStudentList.forEach((studentRow) => {
    examNames.forEach((examName, examIndex) => {
      scoreSubjectNames.forEach((subjectName) => {
        const baseScore = 60 + Math.floor(Math.random() * 40)
        studentScores.push({
          id: uuid(),
          student_id: studentRow.id,
          student_name: studentRow.student_name,
          subject: subjectName,
          exam_name: examName,
          exam_date: examDates[examIndex],
          score: Math.min(100, Math.max(0, baseScore + (Math.floor(Math.random() * 20) - 10))),
          full_score: 100,
          school_id: sunshineSchoolId,
          class_id: classOneOneId,
          operator_user_id: teacherWangProfileId,
          create_time: examDates[examIndex],
          created_at: examDates[examIndex],
        })
      })
    })
  })

  const borrowItems: BorrowItem[] = [
    { id: uuid(), item_name: '足球', name: '足球', type: '体育器材', total_quantity: 10, available_quantity: 8, school_id: sunshineSchoolId, class_id: classOneOneId, location: '器材室A架', description: '标准5号足球', create_time: today, created_at: today },
    { id: uuid(), item_name: '羽毛球拍', name: '羽毛球拍', type: '体育器材', total_quantity: 15, available_quantity: 12, school_id: sunshineSchoolId, class_id: classOneOneId, location: '器材室A架', description: '铝合金材质羽毛球拍', create_time: today, created_at: today },
    { id: uuid(), item_name: '跳绳', name: '跳绳', type: '体育器材', total_quantity: 30, available_quantity: 25, school_id: sunshineSchoolId, class_id: classOneOneId, location: '器材室B架', description: '标准长度跳绳', create_time: today, created_at: today },
    { id: uuid(), item_name: '篮球', name: '篮球', type: '体育器材', total_quantity: 8, available_quantity: 6, school_id: sunshineSchoolId, class_id: classOneOneId, location: '器材室A架', create_time: today, created_at: today },
    { id: uuid(), item_name: '哑铃套装', name: '哑铃套装', type: '健身器材', total_quantity: 5, available_quantity: 5, school_id: sunshineSchoolId, class_id: classOneOneId, location: '器材室C架', description: '可调节重量', create_time: today, created_at: today },
  ]

  const borrowRecords: BorrowRecord[] = []
  const firstBorrowItems = borrowItems.slice(0, 2)
  firstBorrowItems.forEach((borrowItem, borrowIndex) => {
    const studentRow = students[borrowIndex]
    const borrowDate = new Date(Date.now() - (borrowIndex + 1) * 86400000).toISOString()
    borrowRecords.push({
      id: uuid(),
      item_id: borrowItem.id,
      student_id: studentRow.id,
      borrower_name: studentRow.student_name,
      borrow_date: borrowDate,
      expected_return_date: new Date(Date.now() + 3 * 86400000).toISOString(),
      status: 'borrowed',
      qty: 2,
      school_id: sunshineSchoolId,
      class_id: classOneOneId,
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
    score_log: scoreLogEntries,
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

/**
 * 重置本地 Mock 数据：清空数据库与会话，并重新写入一份种子数据。
 * @returns 无返回值（副作用：清空并重建 localStorage 中的数据）
 */
export function resetMockData(): void {
  localStorage.removeItem(DB_KEY)
  localStorage.removeItem(SESSION_KEY)
  seedDB()
}

/**
 * 读取当前登录会话。
 * @returns 会话对象；未登录时返回 null
 */
function getSession(): MockSession | null {
  const storedSessionJson = localStorage.getItem(SESSION_KEY)
  if (!storedSessionJson) return null
  return JSON.parse(storedSessionJson)
}

/**
 * 写入或清除登录会话。
 * @param session 待保存的会话；传 null 表示退出登录
 * @returns 无返回值（副作用：写入或删除 localStorage 中的会话）
 */
function saveSession(session: MockSession | null): void {
  if (session) localStorage.setItem(SESSION_KEY, JSON.stringify(session))
  else localStorage.removeItem(SESSION_KEY)
}

/**
 * 判断当前是否走本地 Mock 后端。
 * 开发环境下默认开启；生产环境下由 localStorage 中的开关决定。
 * @returns true 表示使用 Mock 数据，false 表示走真实 Supabase
 */
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

/**
 * 把业务用户档案转换成 Supabase 风格的登录用户对象。
 * @param profile 业务侧的 profiles 记录
 * @returns 带 user_metadata 的 MockUser
 */
function profileToUser(profile: Profile): MockUser {
  return {
    id: profile.id,
    email: profile.email,
    user_metadata: {
      role: profile.role,
      name: profile.real_name,
      phone: profile.phone,
      school_id: profile.school_id,
      class_id: profile.class_id,
      class_name: profile.class_name,
    },
    aud: 'authenticated',
    created_at: profile.create_time,
  }
}

/**
 * 取当前会话对应的用户档案（含身份切换覆盖）。
 * @returns 用户档案；未登录或档案不存在时返回 null
 */
function currentProfile(): Profile | null {
  const session = getSession()
  if (!session) return null
  const db = getDB()
  const profile = db.profiles.find((profileRow) => profileRow.id === session.user.id) ?? null
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
  const storedClassId = localStorage.getItem('MOCK_SELECTED_CLASS')
  if (storedClassId) return storedClassId
  const profile = currentProfile()
  return profile?.class_id ?? null
}

/**
 * 应用「身份切换」覆盖：把 user_metadata.role 换成开发者临时切换的角色。
 * @param user 原始登录用户
 * @returns 覆盖角色后的用户对象；无有效覆盖时原样返回
 */
function applyRoleOverride(user: MockUser): MockUser {
  // 注意：前端只认 sys_admin / school_admin / teacher 三种角色值，
  // 若角色取到其它值（如 super_admin），菜单会渲染为空并导致页面卡死（见 DEPLOY-LESSONS 第九节）
  const override = localStorage.getItem('MOCK_ROLE_OVERRIDE') as Role | null
  if (override && ['sys_admin', 'school_admin', 'teacher'].includes(override)) {
    return {
      ...user,
      user_metadata: { ...user.user_metadata, role: override },
    }
  }
  return user
}

/**
 * 本地模拟 RLS：按当前登录用户的角色和班级，对查询结果做行级过滤。
 * 仅用于 Mock 模式，让不同角色看到的数据范围与线上 RLS 策略保持一致。
 * @param table 表名
 * @param rows 待过滤的原始数据行
 * @param action 即将执行的操作类型
 * @returns 过滤后可被当前用户访问的数据行
 */
function rlsFilter<T extends Record<string, any>>(table: string, rows: T[], action: 'select' | 'insert' | 'update' | 'delete'): T[] {
  const profile = currentProfile()
  if (!profile) {
    if (action === 'select') return rows
    return rows
  }
  if (profile.role === 'sys_admin') return rows
  switch (table) {
    case 'schools':
      if (profile.role === 'school_admin') return rows.filter((tableRow) => tableRow.id === profile.school_id)
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
        const adminClassIds = db.classes.filter((classRow) => classRow.school_id === profile.school_id).map((classRow) => classRow.id)
        return rows.filter((tableRow) => {
          if (table === 'students' || table === 'classes') return adminClassIds.includes(tableRow.class_id ?? tableRow.id) || tableRow.school_id === profile.school_id
          if (table === 'homework_subjects') return tableRow.school_id === profile.school_id
          if (table === 'homework_records' || table === 'homework_notes') return tableRow.school_id === profile.school_id && adminClassIds.includes(tableRow.class_id)
          if (table === 'score_log' || table === 'borrow_records' || table === 'student_awards' || table === 'student_scores') {
            const studentRecord = db.students.find((studentRow) => studentRow.id === tableRow.student_id)
            return studentRecord ? adminClassIds.includes(studentRecord.class_id) : false
          }
          if (table === 'profiles') return tableRow.school_id === profile.school_id || tableRow.id === profile.id
          return false
        })
      }
      if (profile.role === 'teacher') {
        const db = getDB()
        // 教师可以查看自己学校任何班级的数据，但通过 MainLayout 的班级切换器决定"当前查看哪一个班"
        // 后端（成绩/仪表盘）是否允许写入由 MainLayout 的菜单显隐控制
        const selectedClassId = getSelectedClassId() ?? profile.class_id
        // classes 表：让学校的所有班级都可见（这样教师可以切班级）
        const schoolClassIds = db.classes.filter((classRow) => classRow.school_id === profile.school_id).map((classRow) => classRow.id)
        return rows.filter((tableRow) => {
          if (table === 'classes') return schoolClassIds.includes(tableRow.id)
          if (table === 'homework_subjects') return tableRow.school_id === profile.school_id
          if (table === 'students') return tableRow.class_id === selectedClassId
          if (table === 'homework_records' || table === 'homework_notes') return tableRow.class_id === selectedClassId
          if (table === 'score_log' || table === 'borrow_records' || table === 'student_awards' || table === 'student_scores') {
            const studentRecord = db.students.find((studentRow) => studentRow.id === tableRow.student_id)
            return studentRecord ? studentRecord.class_id === selectedClassId : false
          }
          return false
        })
      }
      return rows
    }
    case 'borrow_items': {
      if (profile.role === 'school_admin') {
        return rows.filter((tableRow) => tableRow.school_id === profile.school_id)
      }
      if (profile.role === 'teacher') {
        return rows.filter((tableRow) => tableRow.class_id === profile.class_id)
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
  eq: (col: string, filterValue: FilterValue) => FilterChain
  neq: (col: string, filterValue: FilterValue) => FilterChain
  gt: (col: string, filterValue: number) => FilterChain
  gte: (col: string, filterValue: number) => FilterChain
  lt: (col: string, filterValue: number) => FilterChain
  lte: (col: string, filterValue: number) => FilterChain
  in: (col: string, filterValues: FilterValue[]) => FilterChain
  like: (col: string, pattern: string) => FilterChain
  ilike: (col: string, pattern: string) => FilterChain
  order: (col: string, orderOptions?: { ascending?: boolean }) => FilterChain
  limit: (maxRowCount: number) => FilterChain
  select: (columns?: string) => Promise<{ data: any[]; error: null }>
  maybeSingle: () => Promise<{ data: any | null; error: null }>
  single: () => Promise<{ data: any; error: null }>
}

type QueryResult = { data: any[]; error: null; count?: number }

/**
 * 模拟 supabase-js 的链式查询构造器（PostgREST 风格）。
 * 依次累积 eq / in / order / limit 等条件，最终在 _execute 中对本地数据做 RLS 过滤、条件筛选、排序与分页。
 */
class QueryChain implements FilterChain {
  private filters: ((tableRow: any) => boolean)[] = []
  private orderColumn: string | null = null
  private orderAscending: boolean = true
  private limitRowCount: number | null = null
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

  eq(col: string, filterValue: FilterValue): this { this.filters.push((tableRow) => tableRow[col] === filterValue); return this }
  neq(col: string, filterValue: FilterValue): this { this.filters.push((tableRow) => tableRow[col] !== filterValue); return this }
  gt(col: string, filterValue: number): this { this.filters.push((tableRow) => Number(tableRow[col]) > filterValue); return this }
  gte(col: string, filterValue: number): this { this.filters.push((tableRow) => Number(tableRow[col]) >= filterValue); return this }
  lt(col: string, filterValue: number): this { this.filters.push((tableRow) => Number(tableRow[col]) < filterValue); return this }
  lte(col: string, filterValue: number): this { this.filters.push((tableRow) => Number(tableRow[col]) <= filterValue); return this }
  in(col: string, filterValues: FilterValue[]): this { this.filters.push((tableRow) => filterValues.includes(tableRow[col])); return this }
  like(col: string, pattern: string): this {
    const keyword = pattern.replace(/%/g, '')
    this.filters.push((tableRow) => String(tableRow[col] ?? '').includes(keyword)); return this
  }
  ilike(col: string, pattern: string): this {
    const keyword = pattern.replace(/%/g, '').toLowerCase()
    this.filters.push((tableRow) => String(tableRow[col] ?? '').toLowerCase().includes(keyword)); return this
  }
  order(col: string, orderOptions?: { ascending?: boolean }): this {
    this.orderColumn = col
    this.orderAscending = orderOptions?.ascending !== false; return this
  }
  limit(maxRowCount: number): this { this.limitRowCount = maxRowCount; return this }

  /**
   * 执行查询并按 supabase-js 的 select 约定返回结果。
   * @param _columns 需要返回的列（Mock 中忽略，始终返回整行）
   * @param opts select 选项（count / head）
   * @returns 查询结果的 Promise
   */
  select(_columns?: string, opts?: { count?: 'exact' | 'planned'; head?: boolean }): Promise<QueryResult> {
    this.selectOpts = opts
    return Promise.resolve(this._execute(opts))
  }

  /**
   * 执行查询并只取第一行，无数据时返回 null。
   * @returns 单行数据的 Promise
   */
  maybeSingle(): Promise<{ data: any | null; error: null }> {
    return Promise.resolve(this._execute()).then((queryResult) => ({
      data: queryResult.data.length > 0 ? queryResult.data[0] : null,
      error: null,
    }))
  }

  /**
   * 执行查询并只取第一行（与 supabase-js 行为一致，无数据时返回 null）。
   * @returns 单行数据的 Promise
   */
  single(): Promise<{ data: any; error: null }> {
    return Promise.resolve(this._execute()).then((queryResult) => ({
      data: queryResult.data[0] ?? null,
      error: null,
    }))
  }

  /**
   * 对数据行依次应用已累积的条件筛选、排序与分页限制。
   * @param rows 待处理的数据行
   * @returns 处理后的数据行
   */
  private _applyFilters(rows: any[]): any[] {
    let matchedRows = rows.filter((tableRow) => this.filters.every((filterFn) => filterFn(tableRow)))
    if (this.orderColumn) {
      matchedRows = [...matchedRows].sort((rowA, rowB) => {
        const valueA = rowA[this.orderColumn!]
        const valueB = rowB[this.orderColumn!]
        if (valueA < valueB) return this.orderAscending ? -1 : 1
        if (valueA > valueB) return this.orderAscending ? 1 : -1
        return 0
      })
    }
    if (this.limitRowCount !== null) matchedRows = matchedRows.slice(0, this.limitRowCount!)
    return matchedRows
  }

  /**
   * 按当前 action 落地查询：select 走只读过滤，update / delete 直接改写本地库。
   * 借阅记录状态在「借出中 ↔ 已归还」之间变化时，同步增减对应物品的可用数量。
   * @param selectOpts 仅 select 场景使用的 count / head 选项
   * @returns 统一的 { data, error } 结果
   */
  private _execute(selectOpts?: { count?: 'exact' | 'planned'; head?: boolean }): QueryResult {
    const db = getDB()
    const tableKey = this.tableName as keyof Database
    const allRows: any[] = [...(db[tableKey] as any[])]

    if (this.action === 'select') {
      const rlsRows = rlsFilter(this.tableName, allRows, 'select')
      const visibleRows = this._applyFilters(rlsRows)
      // head + count 模式：只返回 count，不返回 data 内容
      if (selectOpts?.count && selectOpts?.head) {
        return { data: [], error: null, count: visibleRows.length }
      }
      // count 模式：data 正常返回，附带 count
      if (selectOpts?.count) {
        return { data: visibleRows, error: null, count: visibleRows.length }
      }
      return { data: visibleRows, error: null }
    }

    if (this.action === 'update') {
      const rowsToUpdate = this._applyFilters(allRows)
      if (this.tableName === 'borrow_records') {
        for (const tableRow of rowsToUpdate) {
          const rowIndex = (db[tableKey] as any[]).findIndex((storedRow) => storedRow.id === tableRow.id)
          if (rowIndex !== -1) {
            const previousRow = (db[tableKey] as any[])[rowIndex]
            const previousStatus = previousRow.status
            const previousQty = Number(previousRow.qty ?? 1)
            const mergedRow = { ...previousRow, ...this.updateData }
            ;(db[tableKey] as any[])[rowIndex] = mergedRow
            if (previousStatus === 'borrowed' && mergedRow.status === 'returned') {
              const borrowItemRow = db.borrow_items.find((borrowItem) => borrowItem.id === previousRow.item_id)
              if (borrowItemRow) borrowItemRow.available_quantity = (borrowItemRow.available_quantity ?? 0) + previousQty
            }
            if (previousStatus === 'returned' && mergedRow.status === 'borrowed') {
              const borrowItemRow = db.borrow_items.find((borrowItem) => borrowItem.id === previousRow.item_id)
              if (borrowItemRow) borrowItemRow.available_quantity = Math.max(0, (borrowItemRow.available_quantity ?? 0) - Number(mergedRow.qty ?? previousQty))
            }
          }
        }
      } else {
        for (const tableRow of rowsToUpdate) {
          const rowIndex = (db[tableKey] as any[]).findIndex((storedRow) => storedRow.id === tableRow.id)
          if (rowIndex !== -1) {
            ;(db[tableKey] as any[])[rowIndex] = { ...(db[tableKey] as any[])[rowIndex], ...this.updateData }
          }
        }
      }
      saveDB(db)
      return { data: rowsToUpdate, error: null }
    }

    if (this.action === 'delete') {
      const rowsToDelete = this._applyFilters(allRows)
      const idsToDelete = new Set(rowsToDelete.map((tableRow) => tableRow.id))
      ;(db[tableKey] as any[]) = (db[tableKey] as any[]).filter((storedRow) => !idsToDelete.has(storedRow.id))
      saveDB(db)
      return { data: rowsToDelete, error: null }
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

/**
 * 模拟 supabase-js 的 from(table) 入口：支持 select / insert / update / delete 四种操作。
 * insert 时自动补齐 id 与创建时间，并在写入借阅记录时同步扣减对应物品的可用数量。
 * @param tableName 目标表名
 * @returns 该表的操作对象
 */
function fromTable(tableName: string) {
  return {
    select(_columns?: string, opts?: { count?: 'exact' | 'planned'; head?: boolean }) {
      return new QueryChain(tableName, 'select', undefined, opts)
    },
    insert(rows: any | any[]) {
      const rowList = Array.isArray(rows) ? rows : [rows]
      rowList.forEach((tableRow: any) => {
        if (!tableRow.id) tableRow.id = uuid()
        if (!tableRow.create_time && !tableRow.created_at) {
          const timestamp = nowISO()
          tableRow.create_time = timestamp
          tableRow.created_at = timestamp
        }
      })
      const db = getDB()
      const tableKey = tableName as keyof Database
      if (tableKey in db) {
        ;(db[tableKey] as any[]).push(...rowList)
      }
      if (tableName === 'borrow_records') {
        for (const recordRow of rowList) {
          if (recordRow.status === 'borrowed' && recordRow.item_id) {
            const borrowItemRow = db.borrow_items.find((borrowItem) => borrowItem.id === recordRow.item_id)
            if (borrowItemRow) borrowItemRow.available_quantity = Math.max(0, (borrowItemRow.available_quantity ?? 0) - Number(recordRow.qty ?? 1))
          }
        }
      }
      saveDB(db)
      return {
        select: () => Promise.resolve({ data: rowList, error: null }),
        then: (callback: any) => Promise.resolve({ data: rowList, error: null }).then(callback),
      }
    },
    update(updateData: Record<string, any>) {
      return new QueryChain(tableName, 'update', updateData)
    },
    delete() {
      return new QueryChain(tableName, 'delete')
    },
  }
}

/**
 * 模拟 supabase-js 的 auth 模块：登录、登出、读取当前会话与用户。
 * 账号密码直接与本地 profiles 表比对，登录成功后写入本地会话。
 */
const mockAuth = {
  /**
   * 账号密码登录。
   * @param credentials 登录邮箱（或手机号）与密码
   * @returns 登录后的用户与会话；失败时通过 error.message 返回原因
   */
  signInWithPassword: async ({ email, password }: { email: string; password: string }): Promise<{ data: { user: MockUser | null; session: MockSession | null }; error: any }> => {
    await new Promise((resolve) => setTimeout(resolve, 300))
    const db = getDB()
    const profileRow = db.profiles.find((profile) => (profile.phone === email || profile.email === email) && profile.password === password)
    if (!profileRow) {
      return { data: { user: null, session: null }, error: { message: '账号或密码错误' } }
    }
    if (profileRow.status !== 'active') {
      return { data: { user: null, session: null }, error: { message: '账号已被禁用' } }
    }
    const user = profileToUser(profileRow)
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
  /**
   * 退出登录并清空本地会话。
   * @returns 固定返回 error: null
   */
  signOut: async (): Promise<{ error: any }> => {
    await new Promise((resolve) => setTimeout(resolve, 100))
    saveSession(null)
    return { error: null }
  },
  /**
   * 读取当前会话（含开发者的身份切换覆盖）。
   * @returns 当前会话；未登录时为 null
   */
  getSession: async (): Promise<{ data: { session: MockSession | null }; error: any }> => {
    const session = getSession()
    if (!session) return { data: { session: null }, error: null }
    const overriddenUser = applyRoleOverride(session.user)
    return {
      data: { session: { ...session, user: overriddenUser } },
      error: null,
    }
  },
  /**
   * 读取当前登录用户（含开发者的身份切换覆盖）。
   * @returns 当前用户；未登录时为 null
   */
  getUser: async (): Promise<{ data: { user: MockUser | null }; error: any }> => {
    const session = getSession()
    if (!session) return { data: { user: null }, error: null }
    return { data: { user: applyRoleOverride(session.user) }, error: null }
  },
  /**
   * 订阅登录状态变化。Mock 模式下不做真实订阅，返回一个可取消的空订阅对象。
   * @param _callback 状态变化回调（Mock 模式下不会被调用）
   * @returns 含 unsubscribe 的订阅对象
   */
  onAuthStateChange: (_callback: (event: string, session: MockSession | null) => void) => {
    return { data: { subscription: { unsubscribe: () => {} } } }
  },
}

/**
 * 模拟 supabase-js 的 rpc 调用，目前实现积分变动函数 fn_change_student_score。
 * @param name 数据库函数名
 * @param params 函数入参（参数名与真实数据库函数保持一致）
 * @returns 执行结果；函数名未知或参数非法时通过 error.message 返回原因
 */
function rpc(name: string, params: Record<string, any>): Promise<{ data: any; error: any }> {
  return Promise.resolve().then(() => {
    if (name === 'fn_change_student_score') {
      const { p_student_id, p_score_change, p_remark } = params
      const db = getDB()
      const targetStudent = db.students.find((studentRow) => studentRow.id === p_student_id)
      if (!targetStudent) return { data: null, error: { message: '学生不存在' } }
      const scoreChange = Number(p_score_change)
      if (isNaN(scoreChange)) return { data: null, error: { message: '积分变化值无效' } }
      targetStudent.total_score = (targetStudent.total_score ?? 0) + scoreChange
      const session = getSession()
      const scoreLogEntry: ScoreLog = {
        id: uuid(),
        student_id: p_student_id,
        subject: '积分调整',
        score_change: scoreChange,
        score: scoreChange,
        score_type: 'daily',
        record_date: nowISO(),
        operate_user_id: session?.user.id,
        teacher_id: session?.user.id,
        school_id: targetStudent.school_id,
        class_id: targetStudent.class_id,
        remark: p_remark ?? '',
        create_time: nowISO(),
        created_at: nowISO(),
      }
      db.score_log.push(scoreLogEntry)
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
