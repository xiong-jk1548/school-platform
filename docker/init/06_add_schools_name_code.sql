-- ============================================================
-- 给 schools 表加 name + code 列，兼容前端字段命名
-- TRIGGER 双向同步：前端传 name/code 自动填 school_name/school_code
--
-- 背景（"新增学校 400 Bad Request"那次排查）：
--   教育局端表单提交的是 name / code，而建表时库里只有 school_name / school_code，
--   PostgREST 找不到对应列直接返回 400。当时的取舍是"加兼容列 + 双向 trigger"，
--   而不是回头改前端，于是有了本文件。
-- 列的主从约定：school_name / school_code 为主列，UPDATE 时两者不一致以主列为准。
-- 幂等：可重复执行（加列用 IF NOT EXISTS，加约束靠 EXCEPTION 兜住重复）
-- ============================================================

ALTER TABLE public.schools ADD COLUMN IF NOT EXISTS name text;
ALTER TABLE public.schools ADD COLUMN IF NOT EXISTS code text;

UPDATE public.schools SET name = COALESCE(name, school_name);
UPDATE public.schools SET code = COALESCE(code, school_code);

ALTER TABLE public.schools ALTER COLUMN name SET NOT NULL;
ALTER TABLE public.schools ALTER COLUMN code SET NOT NULL;

-- PG 的 ADD CONSTRAINT 没有 IF NOT EXISTS 写法，只能靠捕获 duplicate_object 做幂等
DO $$ BEGIN
  BEGIN ALTER TABLE public.schools ADD CONSTRAINT schools_code_key UNIQUE (code);
  EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- 双向同步 BEFORE trigger
CREATE OR REPLACE FUNCTION public.trg_schools_sync_name() RETURNS trigger AS $$
BEGIN
  -- name → school_name
  IF NEW.school_name IS NULL AND NEW.name IS NOT NULL THEN
    NEW.school_name := NEW.name;
  ELSIF NEW.school_name IS NOT NULL AND NEW.name IS NULL THEN
    NEW.name := NEW.school_name;
  END IF;

  -- code → school_code
  IF NEW.school_code IS NULL AND NEW.code IS NOT NULL THEN
    NEW.school_code := NEW.code;
  ELSIF NEW.school_code IS NOT NULL AND NEW.code IS NULL THEN
    NEW.code := NEW.school_code;
  END IF;

  -- UPDATE 时如果两个都给了，以 PRIMARY 列（school_name/school_code）为准
  IF TG_OP = 'UPDATE' THEN
    IF NEW.school_name IS DISTINCT FROM NEW.name THEN
      NEW.name := NEW.school_name;
    END IF;
    IF NEW.school_code IS DISTINCT FROM NEW.code THEN
      NEW.code := NEW.school_code;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_schools_sync_name ON public.schools;
CREATE TRIGGER trg_schools_sync_name
  BEFORE INSERT OR UPDATE ON public.schools
  FOR EACH ROW EXECUTE FUNCTION public.trg_schools_sync_name();

SELECT school_name, name, school_code, code FROM public.schools;
