-- ============================================================
-- 班级检查扣分（卫生 / 做操）
-- 支持按天登分、按周汇总排名、按年级排名、自定义时间范围统计
--
-- 执行：docker exec -i supabase-db psql -U supabase -d postgres < docker/init/10_class_inspection.sql
-- ============================================================

-- --------------------------------------------------
-- 1) 检查扣分明细表
-- --------------------------------------------------
CREATE TABLE IF NOT EXISTS public.class_inspection_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  inspect_date DATE NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('卫生', '做操')),
  score NUMERIC(10,2) NOT NULL DEFAULT 0,
  remark TEXT,
  operator_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 兼容旧库：若存在"仅扣分"约束（score <= 0），删除以支持加分
ALTER TABLE public.class_inspection_records
  DROP CONSTRAINT IF EXISTS class_inspection_records_score_check;

-- 同一天、同一班级、同一检查项只能有一条记录（Upsert 依据）
CREATE UNIQUE INDEX IF NOT EXISTS idx_class_inspection_unique
  ON public.class_inspection_records (class_id, inspect_date, category);

CREATE INDEX IF NOT EXISTS idx_class_inspection_school_date
  ON public.class_inspection_records (school_id, inspect_date);

CREATE INDEX IF NOT EXISTS idx_class_inspection_class_date
  ON public.class_inspection_records (class_id, inspect_date);

-- --------------------------------------------------
-- 2) 更新时间戳触发器
-- --------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_class_inspection_updated_at ON public.class_inspection_records;
CREATE TRIGGER trg_class_inspection_updated_at
  BEFORE UPDATE ON public.class_inspection_records
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- --------------------------------------------------
-- 3) RLS（沿用 09_school_isolation_rls.sql 风格）
--    sys_admin 全部；school_admin 限本校；teacher 本校只读
-- --------------------------------------------------
ALTER TABLE public.class_inspection_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "class_inspection sys all"          ON public.class_inspection_records;
DROP POLICY IF EXISTS "class_inspection school admin all" ON public.class_inspection_records;
DROP POLICY IF EXISTS "class_inspection teacher read"     ON public.class_inspection_records;

CREATE POLICY "class_inspection sys all" ON public.class_inspection_records
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "class_inspection school admin all" ON public.class_inspection_records
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "class_inspection teacher read" ON public.class_inspection_records
  FOR SELECT TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- --------------------------------------------------
-- 4) fn_class_grade_number(p_class_name TEXT) RETURNS INTEGER
--    按班级名称前缀推断年级序号：'101' -> 1，'201' -> 2
--    @param p_class_name 班级名称，约定以"年级序号 + 班号"开头（101 即 1 年级 1 班）
--    @return 推断出的年级序号；名称不以数字开头时返回 NULL，由调用方兜底
--    @note 取的是前缀数字的首位，所以 '101' 和 '1012' 都会被判成 1 年级
--    @note 标 IMMUTABLE：纯字符串运算、不依赖 now() 之类易变函数，可安全内联
-- --------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_class_grade_number(p_class_name TEXT)
RETURNS INTEGER AS $$
DECLARE
  v_prefix TEXT;
BEGIN
  v_prefix := substring(p_class_name from '^[0-9]+');
  IF v_prefix IS NOT NULL AND length(v_prefix) > 0 THEN
    RETURN left(v_prefix, 1)::INTEGER;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
