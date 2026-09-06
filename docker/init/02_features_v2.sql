-- ============================================================
-- V2 增量脚本 —— 作业管理 + 物品借阅
-- 升级时执行（已部署过 V1 的数据库跑这个）
-- 全部使用 IF NOT EXISTS，可重复安全重跑
-- 执行方式：
--   docker exec -i supabase-db psql -U supabase -d postgres < 02_features_v2.sql
-- ============================================================

-- ---------------------- 模块一：作业完成情况管理 ----------------------

-- 1. 科目表：学校级别的科目配置
CREATE TABLE IF NOT EXISTS public.homework_subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    subject_name TEXT NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(school_id, subject_name)
);

CREATE INDEX IF NOT EXISTS idx_hw_subject_school ON public.homework_subjects(school_id);

ALTER TABLE public.homework_subjects ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS policy_hw_subject_sys_read ON public.homework_subjects
FOR SELECT TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='sys_admin');

CREATE POLICY IF NOT EXISTS policy_hw_subject_school_admin ON public.homework_subjects
FOR ALL TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='school_admin'
       AND homework_subjects.school_id = (SELECT school_id FROM public.profiles WHERE id=auth.uid()));

CREATE POLICY IF NOT EXISTS policy_hw_subject_teacher_read ON public.homework_subjects
FOR SELECT TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='teacher'
       AND homework_subjects.school_id = (SELECT school_id FROM public.profiles WHERE id=auth.uid()));

-- 2. 作业完成记录表：每生每科目每天一条
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
    UNIQUE(student_id, subject_id, record_date)
);

CREATE INDEX IF NOT EXISTS idx_hw_record_class_date ON public.homework_records(class_id, record_date);
CREATE INDEX IF NOT EXISTS idx_hw_record_student ON public.homework_records(student_id);

ALTER TABLE public.homework_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS policy_hw_record_sys_read ON public.homework_records
FOR SELECT TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='sys_admin');

CREATE POLICY IF NOT EXISTS policy_hw_record_school_admin ON public.homework_records
FOR ALL TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='school_admin'
       AND homework_records.school_id = (SELECT school_id FROM public.profiles WHERE id=auth.uid()));

CREATE POLICY IF NOT EXISTS policy_hw_record_teacher ON public.homework_records
FOR ALL TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='teacher'
       AND homework_records.class_id = (SELECT class_id FROM public.profiles WHERE id=auth.uid()));

-- ---------------------- 模块二：班级公共物品借阅登记 ----------------------

-- 1. 物品表：班级级别的物品库
CREATE TABLE IF NOT EXISTS public.borrow_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    item_name TEXT NOT NULL,
    total_qty INT NOT NULL DEFAULT 1,
    available_qty INT NOT NULL DEFAULT 1,
    location TEXT,
    remark TEXT,
    create_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (available_qty >= 0),
    CHECK (available_qty <= total_qty)
);

CREATE INDEX IF NOT EXISTS idx_borrow_item_class ON public.borrow_items(class_id);

ALTER TABLE public.borrow_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS policy_borrow_item_sys_read ON public.borrow_items
FOR SELECT TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='sys_admin');

CREATE POLICY IF NOT EXISTS policy_borrow_item_school_admin ON public.borrow_items
FOR ALL TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='school_admin'
       AND borrow_items.school_id = (SELECT school_id FROM public.profiles WHERE id=auth.uid()));

CREATE POLICY IF NOT EXISTS policy_borrow_item_teacher ON public.borrow_items
FOR ALL TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='teacher'
       AND borrow_items.class_id = (SELECT class_id FROM public.profiles WHERE id=auth.uid()));

-- 2. 借还记录表
CREATE TABLE IF NOT EXISTS public.borrow_records (
    id BIGSERIAL PRIMARY KEY,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES public.borrow_items(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    qty INT NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'borrowed', -- borrowed / returned
    borrow_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    return_time TIMESTAMPTZ,
    operator_user_id UUID NOT NULL REFERENCES auth.users(id),
    remark TEXT
);

CREATE INDEX IF NOT EXISTS idx_borrow_record_item ON public.borrow_records(item_id);
CREATE INDEX IF NOT EXISTS idx_borrow_record_student ON public.borrow_records(student_id);
CREATE INDEX IF NOT EXISTS idx_borrow_record_class ON public.borrow_records(class_id);

ALTER TABLE public.borrow_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS policy_borrow_record_sys_read ON public.borrow_records
FOR SELECT TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='sys_admin');

CREATE POLICY IF NOT EXISTS policy_borrow_record_school_admin ON public.borrow_records
FOR ALL TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='school_admin'
       AND borrow_records.school_id = (SELECT school_id FROM public.profiles WHERE id=auth.uid()));

CREATE POLICY IF NOT EXISTS policy_borrow_record_teacher ON public.borrow_records
FOR ALL TO authenticated
USING ((SELECT role FROM public.profiles WHERE id=auth.uid())='teacher'
       AND borrow_records.class_id = (SELECT class_id FROM public.profiles WHERE id=auth.uid()));

-- 3. 物品可用数量自动维护触发器
CREATE OR REPLACE FUNCTION public.fn_update_borrow_available()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'borrowed' THEN
        UPDATE public.borrow_items SET available_qty = available_qty - NEW.qty
        WHERE id = NEW.item_id AND available_qty >= NEW.qty;
    ELSIF TG_OP = 'UPDATE' AND OLD.status = 'borrowed' AND NEW.status = 'returned' THEN
        UPDATE public.borrow_items SET available_qty = available_qty + NEW.qty
        WHERE id = NEW.item_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_borrow_record_change ON public.borrow_records;
CREATE TRIGGER trg_borrow_record_change
AFTER INSERT OR UPDATE OF status ON public.borrow_records
FOR EACH ROW EXECUTE FUNCTION public.fn_update_borrow_available();
