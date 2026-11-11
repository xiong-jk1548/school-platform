-- ============================================================
-- 严格按校/按班隔离 RLS（修复跨校数据泄漏）
-- 设计：用 auth.jwt() -> 'user_metadata' 拿到 role/school_id/class_id
--      （这些字段由 08_fix_seed_auth.sql 写入），完全不依赖 profiles 表，
--      避免 profiles 策略自递归导致的 "infinite recursion" 错误。
--
--    - sys_admin           ：全表可读可写
--    - school_admin        ：本校所有表可读 + 可写（限本校 school_id）
--    - teacher             ：**分两类**，见下
--    - 登录用户总能看到自己的 profiles（用于右上角显示用户名）
--
-- teacher 的粒度按数据敏感度分两类
--   A. 全校可看可改（限本校，绝不跨校）：借阅、作业、积分
--      borrow_items / borrow_records / homework_records / homework_notes / score_log
--      —— 这些是校内公开的日常数据，教师需要跨班协作，故按 school_id 放行。
--   B. 仅本班（成绩，较私密）：student_scores
--      —— 默认只有本班班主任可读写；班主任可通过 grade_access_grants
--         额外授权本校其他老师访问（授权即可读写），授权范围不得跨校。
--      成绩的"班主任"判定见 public.fn_is_homeroom_of()：classes.homeroom_teacher_id
--      与 profiles.class_id 任一命中即可（项目里这两处由班级管理页同步维护，
--      但种子数据只填了 profiles.class_id，故取"或"以兼容）。
--
-- 执行：docker exec -i supabase-db psql -U supabase -d postgres < 09_school_isolation_rls.sql
-- ============================================================

-- 通用辅助理解：
--   auth.jwt()                                            -- 当前 JWT (jsonb)
--   auth.jwt() -> 'user_metadata'                         -- 用户元数据 (jsonb)
--   auth.jwt() -> 'user_metadata' ->> 'role'              -- 'sys_admin' / 'school_admin' / 'teacher'
--   auth.jwt() -> 'user_metadata' ->> 'school_id'        -- UUID 字符串
--   auth.jwt() -> 'user_metadata' ->> 'class_id'         -- UUID 字符串

-- ====================================================================
-- 0) 清理所有"自引用 profiles"的旧策略（避免递归）
--    凡是 USING 子句里查 profiles 表的策略全部丢弃
-- ====================================================================
-- 坑：profiles 的策略里如果再去 SELECT profiles，Postgres 判定策略自引用，
--     直接抛 "infinite recursion detected in policy for relation"，整张表读写全废。
--     所以这里先把所有"USING 子句里查过 profiles"的旧策略一次性清干净。
DO $$
DECLARE policy_rec record;
BEGIN
  FOR policy_rec IN
    SELECT policyname, tablename
    FROM pg_policies
    WHERE schemaname='public'
      AND (qual LIKE '%profiles.%'
           OR qual LIKE '%FROM profiles %'
           OR qual LIKE '%FROM public.profiles%')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', policy_rec.policyname, policy_rec.tablename);
  END LOOP;
END $$;

-- ====================================================================
-- 0.5) 辅助判定函数（成绩授权用）
--      ⚠️ 必须写成 SECURITY DEFINER：策略表达式里若直接 SELECT 其它表，
--      那张表的 RLS 会叠加进来（classes / grade_access_grants 都对 teacher 有策略），
--      既可能误判也可能触发策略递归。函数以属主身份执行即可绕开。
--      ⚠️ 策略里"调函数"而不是"写子查询"，还有一个好处：上面 0) 的清理块会丢弃
--      所有 qual 里含 profiles 的旧策略，写成子查询会被下次重跑误删。
-- ====================================================================

-- 判断当前登录用户是否为指定班级的班主任
CREATE OR REPLACE FUNCTION public.fn_is_homeroom_of(p_class_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
               SELECT 1 FROM public.classes c
                WHERE c.id = p_class_id
                  AND c.homeroom_teacher_id = auth.uid()
           )
        OR EXISTS (
               SELECT 1 FROM public.profiles p
                WHERE p.id = auth.uid()
                  AND p.class_id = p_class_id
           );
$$;

COMMENT ON FUNCTION public.fn_is_homeroom_of(uuid) IS
    '当前登录用户是否为该班班主任（classes.homeroom_teacher_id 或 profiles.class_id 任一命中）。';

-- 判断当前登录用户是否已被班主任授权访问指定班级的成绩
CREATE OR REPLACE FUNCTION public.fn_has_grade_access(p_class_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
               SELECT 1 FROM public.grade_access_grants g
                WHERE g.class_id = p_class_id
                  AND g.teacher_id = auth.uid()
           );
$$;

COMMENT ON FUNCTION public.fn_has_grade_access(uuid) IS
    '当前登录用户是否已获得该班成绩的访问授权（由该班班主任在 grade_access_grants 中登记）。';

-- 判断两个账号是否同校（用于"只能授权同校老师"的约束）
CREATE OR REPLACE FUNCTION public.fn_is_same_school_user(p_user_id uuid, p_school_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
               SELECT 1 FROM public.profiles p
                WHERE p.id = p_user_id
                  AND p.school_id = p_school_id
           );
$$;

COMMENT ON FUNCTION public.fn_is_same_school_user(uuid, uuid) IS
    '指定账号是否属于指定学校（成绩授权只允许授权本校老师）。';

-- 策略表达式以查询者身份求值，故这三个函数必须对 authenticated 可执行
GRANT EXECUTE ON FUNCTION public.fn_is_homeroom_of(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_has_grade_access(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_is_same_school_user(uuid, uuid) TO authenticated;

-- ====================================================================
-- 1) profiles —— "登录就能看自己和本校所有 profile"
-- ====================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles sys all"      ON public.profiles;
DROP POLICY IF EXISTS "profiles school admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles teacher read" ON public.profiles;
DROP POLICY IF EXISTS "profiles self read"    ON public.profiles;
DROP POLICY IF EXISTS "profiles readable for all" ON public.profiles;
DROP POLICY IF EXISTS "authenticated full access profiles" ON public.profiles;

-- 任何登录用户都能看自己的 profile（不依赖 profiles 表本身）
CREATE POLICY "profiles self read" ON public.profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid());

-- sys_admin 看/改所有
CREATE POLICY "profiles sys all" ON public.profiles
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

-- school_admin 看/改本校所有 profile
CREATE POLICY "profiles school admin" ON public.profiles
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- teacher 只能看本校 + 自己（不能改其他老师）
CREATE POLICY "profiles teacher read" ON public.profiles
  FOR SELECT TO authenticated
  USING (
    (auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
     AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id')
    OR id = auth.uid()
  );

-- ====================================================================
-- 2) schools —— "登录用户只能看本校（sys_admin 看全部）"
-- ====================================================================
ALTER TABLE public.schools ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "schools sys all"          ON public.schools;
DROP POLICY IF EXISTS "schools school_admin all" ON public.schools;
DROP POLICY IF EXISTS "schools teacher read"     ON public.schools;
DROP POLICY IF EXISTS "schools readable for all" ON public.schools;
DROP POLICY IF EXISTS "authenticated full access schools" ON public.schools;

CREATE POLICY "schools sys all" ON public.schools
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "schools school_admin all" ON public.schools
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "schools teacher read" ON public.schools
  FOR SELECT TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- ====================================================================
-- 3) classes —— 同 schools 模式
-- ====================================================================
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "classes sys all"          ON public.classes;
DROP POLICY IF EXISTS "classes school_admin all" ON public.classes;
DROP POLICY IF EXISTS "classes teacher read"     ON public.classes;
DROP POLICY IF EXISTS "classes readable for all" ON public.classes;
DROP POLICY IF EXISTS "authenticated full access classes" ON public.classes;

CREATE POLICY "classes sys all" ON public.classes
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "classes school_admin all" ON public.classes
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "classes teacher read" ON public.classes
  FOR SELECT TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- ====================================================================
-- 4) students —— school_admin 全权 / teacher 只看本校，写仅本班
-- ====================================================================
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "students sys all"          ON public.students;
DROP POLICY IF EXISTS "students school_admin all" ON public.students;
DROP POLICY IF EXISTS "students teacher read"     ON public.students;
DROP POLICY IF EXISTS "students teacher write"    ON public.students;
DROP POLICY IF EXISTS "students readable for all" ON public.students;
DROP POLICY IF EXISTS "authenticated full access students" ON public.students;

CREATE POLICY "students sys all" ON public.students
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "students school_admin all" ON public.students
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "students teacher read" ON public.students
  FOR SELECT TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "students teacher write" ON public.students
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND class_id::text = auth.jwt() -> 'user_metadata' ->> 'class_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND class_id::text = auth.jwt() -> 'user_metadata' ->> 'class_id'
  );

-- ====================================================================
-- 5) student_awards —— school_admin 全权 / teacher 读+写本校
-- ====================================================================
ALTER TABLE public.student_awards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "student_awards sys all"          ON public.student_awards;
DROP POLICY IF EXISTS "student_awards school_admin all" ON public.student_awards;
DROP POLICY IF EXISTS "student_awards teacher full"     ON public.student_awards;

CREATE POLICY "student_awards sys all" ON public.student_awards
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "student_awards school_admin all" ON public.student_awards
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "student_awards teacher full" ON public.student_awards
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- ====================================================================
-- 6) student_scores —— school_admin 全权 / teacher 读+写「本班 或 已被班主任授权访问的班」
--    成绩属私密数据：教师默认只能碰自己班；需跨班查看/录入时，
--    由该班班主任在 grade_access_grants 里登记授权（授权即可读写，等价于班主任权限）。
-- ====================================================================
ALTER TABLE public.student_scores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "student_scores sys all"          ON public.student_scores;
DROP POLICY IF EXISTS "student_scores school_admin all" ON public.student_scores;
DROP POLICY IF EXISTS "student_scores teacher full"     ON public.student_scores;

CREATE POLICY "student_scores sys all" ON public.student_scores
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "student_scores school_admin all" ON public.student_scores
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "student_scores teacher full" ON public.student_scores
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND (
      class_id::text = auth.jwt() -> 'user_metadata' ->> 'class_id'
      OR public.fn_has_grade_access(class_id)
    )
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND (
      class_id::text = auth.jwt() -> 'user_metadata' ->> 'class_id'
      OR public.fn_has_grade_access(class_id)
    )
  );

-- ====================================================================
-- 7) score_log —— school_admin 全权本校 / teacher 全权本校（积分：校内公开，可跨班协作）
-- ====================================================================
ALTER TABLE public.score_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "score_log sys all"          ON public.score_log;
DROP POLICY IF EXISTS "score_log school_admin all" ON public.score_log;
DROP POLICY IF EXISTS "score_log teacher full"     ON public.score_log;

CREATE POLICY "score_log sys all" ON public.score_log
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "score_log school_admin all" ON public.score_log
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "score_log teacher full" ON public.score_log
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- ====================================================================
-- 8) homework_notes —— school_admin 全权本校 / teacher 全权本校（作业：校内公开，可跨班协作）
-- ====================================================================
ALTER TABLE public.homework_notes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "homework_notes sys all"          ON public.homework_notes;
DROP POLICY IF EXISTS "homework_notes school_admin all" ON public.homework_notes;
DROP POLICY IF EXISTS "homework_notes teacher full"     ON public.homework_notes;

CREATE POLICY "homework_notes sys all" ON public.homework_notes
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "homework_notes school_admin all" ON public.homework_notes
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "homework_notes teacher full" ON public.homework_notes
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- ====================================================================
-- 9) homework_subjects —— 全校教师共享科目（按 school_id 隔离）
--    教师可读 + 可增删改（本校范围）：作业登记里教师自助新增科目
-- ====================================================================
ALTER TABLE public.homework_subjects ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hw_subject sys all"          ON public.homework_subjects;
DROP POLICY IF EXISTS "hw_subject school_admin all" ON public.homework_subjects;
DROP POLICY IF EXISTS "hw_subject teacher read"     ON public.homework_subjects;
DROP POLICY IF EXISTS "hw_subject teacher write"    ON public.homework_subjects;

CREATE POLICY "hw_subject sys all" ON public.homework_subjects
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "hw_subject school_admin all" ON public.homework_subjects
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "hw_subject teacher read" ON public.homework_subjects
  FOR SELECT TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- 教师可自助增删改本校科目（作业登记 / 物品借阅场景）
CREATE POLICY "hw_subject teacher write" ON public.homework_subjects
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- ====================================================================
-- 10) homework_records —— 作业完成（作业：教师全校可看可改，school_admin 看本校）
-- ====================================================================
ALTER TABLE public.homework_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hw_record sys all"          ON public.homework_records;
DROP POLICY IF EXISTS "hw_record school_admin all" ON public.homework_records;
DROP POLICY IF EXISTS "hw_record teacher full"     ON public.homework_records;

CREATE POLICY "hw_record sys all" ON public.homework_records
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "hw_record school_admin all" ON public.homework_records
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "hw_record teacher full" ON public.homework_records
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- ====================================================================
-- 11) borrow_items —— 学校物品（借阅：教师全校可看可改，school_admin 看本校）
-- ====================================================================
ALTER TABLE public.borrow_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "borrow_item sys all"          ON public.borrow_items;
DROP POLICY IF EXISTS "borrow_item school_admin all" ON public.borrow_items;
DROP POLICY IF EXISTS "borrow_item teacher full"     ON public.borrow_items;

CREATE POLICY "borrow_item sys all" ON public.borrow_items
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "borrow_item school_admin all" ON public.borrow_items
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "borrow_item teacher full" ON public.borrow_items
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- ====================================================================
-- 12) borrow_records —— 借阅流水（借阅：教师全校可看可改，school_admin 看本校）
-- ====================================================================
ALTER TABLE public.borrow_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "borrow_record sys all"          ON public.borrow_records;
DROP POLICY IF EXISTS "borrow_record school_admin all" ON public.borrow_records;
DROP POLICY IF EXISTS "borrow_record teacher full"     ON public.borrow_records;

CREATE POLICY "borrow_record sys all" ON public.borrow_records
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "borrow_record school_admin all" ON public.borrow_records
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

CREATE POLICY "borrow_record teacher full" ON public.borrow_records
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- ====================================================================
-- 13) grade_access_grants —— 成绩访问授权名单
--     读：本校范围内可见（老师需要知道"我被授权了哪些班"，班主任需要看本班名单）
--     写：只有该班班主任可增删（且只能授权本校老师）
-- ====================================================================
ALTER TABLE public.grade_access_grants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "gag sys all"          ON public.grade_access_grants;
DROP POLICY IF EXISTS "gag school_admin all" ON public.grade_access_grants;
DROP POLICY IF EXISTS "gag teacher read"     ON public.grade_access_grants;
DROP POLICY IF EXISTS "gag teacher manage"   ON public.grade_access_grants;

CREATE POLICY "gag sys all" ON public.grade_access_grants
  FOR ALL TO authenticated
  USING (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin')
  WITH CHECK (auth.jwt() -> 'user_metadata' ->> 'role' = 'sys_admin');

CREATE POLICY "gag school_admin all" ON public.grade_access_grants
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'school_admin'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- 教师读：本校范围内可见（不跨校）。被授权人据此得知自己能看哪些班的成绩。
CREATE POLICY "gag teacher read" ON public.grade_access_grants
  FOR SELECT TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
  );

-- 教师写：仅该班班主任，且只能授权本校账号
CREATE POLICY "gag teacher manage" ON public.grade_access_grants
  FOR ALL TO authenticated
  USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
    AND public.fn_is_homeroom_of(class_id)
  )
  WITH CHECK (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'teacher'
    AND school_id::text = auth.jwt() -> 'user_metadata' ->> 'school_id'
    AND public.fn_is_homeroom_of(class_id)
    -- 只能授权同校账号：被授权人必须属于同一所学校
    AND public.fn_is_same_school_user(teacher_id, school_id)
  );

-- ====================================================================
-- 验证
-- ====================================================================
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' ORDER BY tablename;
