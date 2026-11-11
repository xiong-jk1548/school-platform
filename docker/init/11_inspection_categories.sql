-- ============================================================
-- 班级检查扣分 —— 检查项目可自定义
-- ============================================================
-- 升级时执行（已部署过的库可重跑，幂等）
-- 执行方式：
--   docker exec -i supabase-db psql -U supabase -d postgres < 11_inspection_categories.sql
-- ============================================================

-- 1) 解除 category 的枚举 CHECK（兼容旧库；新装库本来就没有）
ALTER TABLE public.class_inspection_records
  DROP CONSTRAINT IF EXISTS class_inspection_records_category_check;

-- 2) 项目表：按学校隔离
CREATE TABLE IF NOT EXISTS public.inspection_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(school_id, name)
);

CREATE INDEX IF NOT EXISTS idx_insp_cat_school ON public.inspection_categories(school_id);

-- 3) RLS
ALTER TABLE public.inspection_categories ENABLE ROW LEVEL SECURITY;

-- sys_admin 全部权限
DROP POLICY IF EXISTS "insp_cat sys all" ON public.inspection_categories;
CREATE POLICY "insp_cat sys all" ON public.inspection_categories
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

-- school_admin 仅本校
DROP POLICY IF EXISTS "insp_cat school_admin all" ON public.inspection_categories;
CREATE POLICY "insp_cat school_admin all" ON public.inspection_categories
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- teacher 仅读本校
DROP POLICY IF EXISTS "insp_cat teacher read" ON public.inspection_categories;
CREATE POLICY "insp_cat teacher read" ON public.inspection_categories
  FOR SELECT TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );