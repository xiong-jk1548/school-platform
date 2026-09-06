-- ============================================================
-- 数据库 V3 完整初始化（全量）
-- 执行方式（二选一）：
--   A. Supabase Dashboard SQL 编辑器（http://服务器IP:8000）
--   B. docker exec -i supabase-db psql -U supabase -d postgres < 01_schema.sql
-- 前置条件：docker compose up -d 后，auth 容器已初始化 auth.users
-- ============================================================

-- 清空旧版（仅第一次部署时，已部署过就别跑）
-- DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;

-- 1. 学校表（新增 grade_range 字段）
CREATE TABLE IF NOT EXISTS public.schools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_name TEXT NOT NULL,
    school_code TEXT NOT NULL UNIQUE,
    grade_range JSONB NOT NULL DEFAULT '[]'::jsonb,  -- 年级范围 ["一年级","二年级",...]
    status TEXT NOT NULL DEFAULT 'active',
    address TEXT,
    contact_phone TEXT,
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. 用户扩展表（关联 auth.users；新增 class_name）
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('sys_admin','school_admin','teacher')),
    school_id UUID REFERENCES public.schools(id) ON DELETE SET NULL,
    class_id UUID NULL,         -- 班主任绑定的班级（学科教师为空）
    class_name TEXT,            -- 冗余字段，方便 UI 直接读
    real_name TEXT NOT NULL,
    name TEXT,                  -- 冗余
    phone TEXT,
    email TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    password TEXT,              -- 仅 mock 模式用，真环境不用
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. 班级表（新增 homeroom_teacher_id）
CREATE TABLE IF NOT EXISTS public.classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_name TEXT NOT NULL,
    name TEXT,                  -- 冗余
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    grade TEXT,
    homeroom_teacher_id UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. 学生表（补 birthday）
CREATE TABLE IF NOT EXISTS public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_name TEXT NOT NULL,
    name TEXT,                  -- 冗余
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    student_no TEXT NOT NULL,   -- 年份+班号+学号，如 202401
    gender TEXT CHECK (gender IN ('male','female','other')),
    birthday DATE,
    total_score NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(school_id, student_no)
);

-- 5. 积分流水（完整字段）
CREATE TABLE IF NOT EXISTS public.score_log (
    id BIGSERIAL PRIMARY KEY,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    subject TEXT,
    score_change NUMERIC(10,2) NOT NULL,
    score NUMERIC(10,2),
    score_type TEXT CHECK (score_type IN ('daily','exam','homework')),
    record_date DATE NOT NULL DEFAULT CURRENT_DATE,
    operate_user_id UUID REFERENCES auth.users(id),
    teacher_id UUID REFERENCES auth.users(id),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    class_id UUID REFERENCES public.classes(id) ON DELETE SET NULL,
    remark TEXT,
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 6. 作业科目表
CREATE TABLE IF NOT EXISTS public.homework_subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_name TEXT NOT NULL,
    name TEXT,                  -- 冗余
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    sort_order INT NOT NULL DEFAULT 0,
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(school_id, subject_name)
);

-- 7. 作业完成记录表
CREATE TABLE IF NOT EXISTS public.homework_records (
    id BIGSERIAL PRIMARY KEY,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    subject_id UUID NOT NULL REFERENCES public.homework_subjects(id) ON DELETE CASCADE,
    record_date DATE NOT NULL DEFAULT CURRENT_DATE,
    is_done BOOLEAN NOT NULL DEFAULT FALSE,
    remark TEXT,
    update_user_id UUID REFERENCES auth.users(id),
    update_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(student_id, subject_id, record_date)
);

-- 8. 作业备注表（实际作业内容）
CREATE TABLE IF NOT EXISTS public.homework_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    subject_id UUID NOT NULL REFERENCES public.homework_subjects(id) ON DELETE CASCADE,
    subject_name TEXT,
    record_date DATE NOT NULL DEFAULT CURRENT_DATE,
    content TEXT NOT NULL,
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(class_id, subject_id, record_date)
);

-- 9. 物品表
CREATE TABLE IF NOT EXISTS public.borrow_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_name TEXT NOT NULL,
    type TEXT,
    description TEXT,
    total_quantity INT NOT NULL DEFAULT 1,
    available_quantity INT NOT NULL DEFAULT 1,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    class_id UUID REFERENCES public.classes(id) ON DELETE SET NULL,
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 10. 借阅记录表
CREATE TABLE IF NOT EXISTS public.borrow_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID NOT NULL REFERENCES public.borrow_items(id) ON DELETE CASCADE,
    student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
    borrower_name TEXT,
    status TEXT NOT NULL CHECK (status IN ('borrowed','returned','overdue')) DEFAULT 'borrowed',
    borrow_date DATE NOT NULL DEFAULT CURRENT_DATE,
    actual_return_date DATE,
    expect_return_date DATE,
    remark TEXT,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    class_id UUID REFERENCES public.classes(id) ON DELETE SET NULL,
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 11. 学生获奖表
CREATE TABLE IF NOT EXISTS public.student_awards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    student_name TEXT,
    title TEXT NOT NULL,
    level TEXT,
    award_type TEXT,
    award_date DATE,
    description TEXT,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    class_id UUID REFERENCES public.classes(id) ON DELETE SET NULL,
    operator_user_id UUID REFERENCES auth.users(id),
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 12. 学生成绩表
CREATE TABLE IF NOT EXISTS public.student_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    student_name TEXT,
    subject TEXT NOT NULL,
    subject_id UUID REFERENCES public.homework_subjects(id) ON DELETE SET NULL,
    exam_name TEXT NOT NULL,
    exam_date DATE,
    score NUMERIC(10,2) NOT NULL,
    full_score NUMERIC(10,2) NOT NULL DEFAULT 100,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    class_id UUID REFERENCES public.classes(id) ON DELETE SET NULL,
    operator_user_id UUID REFERENCES auth.users(id),
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------- 索引 ----------------------
CREATE INDEX IF NOT EXISTS idx_profiles_school ON public.profiles(school_id);
CREATE INDEX IF NOT EXISTS idx_profiles_class ON public.profiles(class_id);
CREATE INDEX IF NOT EXISTS idx_classes_school ON public.classes(school_id);
CREATE INDEX IF NOT EXISTS idx_classes_homeroom ON public.classes(homeroom_teacher_id);
CREATE INDEX IF NOT EXISTS idx_students_school ON public.students(school_id);
CREATE INDEX IF NOT EXISTS idx_students_class ON public.students(class_id);
CREATE INDEX IF NOT EXISTS idx_score_log_school ON public.score_log(school_id);
CREATE INDEX IF NOT EXISTS idx_score_log_student ON public.score_log(student_id);
CREATE INDEX IF NOT EXISTS idx_score_log_operator ON public.score_log(operate_user_id);
CREATE INDEX IF NOT EXISTS idx_hw_records_class_date ON public.homework_records(class_id, record_date);
CREATE INDEX IF NOT EXISTS idx_hw_notes_class_date ON public.homework_notes(class_id, record_date);
CREATE INDEX IF NOT EXISTS idx_borrow_records_item ON public.borrow_records(item_id);
CREATE INDEX IF NOT EXISTS idx_awards_student ON public.student_awards(student_id);
CREATE INDEX IF NOT EXISTS idx_scores_student ON public.student_scores(student_id);

-- ---------------------- 开启 RLS ----------------------
ALTER TABLE public.schools          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.score_log        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.homework_subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.homework_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.homework_notes   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.borrow_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.borrow_records   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_awards   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_scores   ENABLE ROW LEVEL SECURITY;

-- ---------------------- 积分变更 RPC（原子操作） ----------------------
CREATE OR REPLACE FUNCTION public.fn_change_student_score(
    p_student_id UUID,
    p_score_change NUMERIC,
    p_subject TEXT DEFAULT NULL,
    p_score_type TEXT DEFAULT 'daily',
    p_remark TEXT DEFAULT NULL
) RETURNS NUMERIC AS $$
DECLARE
    new_total NUMERIC;
    v_student RECORD;
BEGIN
    SELECT * INTO v_student FROM public.students WHERE id = p_student_id;
    IF v_student IS NULL THEN RAISE EXCEPTION '学生不存在'; END IF;

    UPDATE public.students
    SET total_score = total_score + p_score_change
    WHERE id = p_student_id
    RETURNING total_score INTO new_total;

    INSERT INTO public.score_log
        (student_id, subject, score_change, score, score_type, operate_user_id,
         teacher_id, school_id, class_id, remark, record_date)
    VALUES
        (p_student_id, p_subject, p_score_change, p_score_change, p_score_type, auth.uid(),
         auth.uid(), v_student.school_id, v_student.class_id, p_remark, CURRENT_DATE);

    RETURN new_total;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
