-- 创建 anon / authenticated / service_role role
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOINHERIT NOLOGIN BYPASSRLS;
  END IF;
END $$;

-- 基础权限
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated, service_role;

-- RLS 策略：允许 authenticated 用户访问自己相关的数据
DO $$ BEGIN
  -- schools: 所有人可读
  DROP POLICY IF EXISTS "schools readable for all" ON public.schools;
  CREATE POLICY "schools readable for all" ON public.schools FOR SELECT USING (true);

  -- profiles: 所有人可读
  DROP POLICY IF EXISTS "profiles readable for all" ON public.profiles;
  CREATE POLICY "profiles readable for all" ON public.profiles FOR SELECT USING (true);

  -- classes: 所有人可读
  DROP POLICY IF EXISTS "classes readable for all" ON public.classes;
  CREATE POLICY "classes readable for all" ON public.classes FOR SELECT USING (true);

  -- students: 所有人可读
  DROP POLICY IF EXISTS "students readable for all" ON public.students;
  CREATE POLICY "students readable for all" ON public.students FOR SELECT USING (true);

  -- 其他表暂时允许 authenticated 全部操作
  DROP POLICY IF EXISTS "authenticated can insert schools" ON public.schools;
  CREATE POLICY "authenticated full access schools" ON public.schools FOR ALL USING (auth.uid() IS NOT NULL);
  
  DROP POLICY IF EXISTS "authenticated full access classes" ON public.classes;
  CREATE POLICY "authenticated full access classes" ON public.classes FOR ALL USING (auth.uid() IS NOT NULL);
  
  DROP POLICY IF EXISTS "authenticated full access students" ON public.students;
  CREATE POLICY "authenticated full access students" ON public.students FOR ALL USING (auth.uid() IS NOT NULL);
  
  DROP POLICY IF EXISTS "authenticated full access profiles" ON public.profiles;
  CREATE POLICY "authenticated full access profiles" ON public.profiles FOR ALL USING (auth.uid() IS NOT NULL);
END $$;

SELECT 'Roles and policies configured!' as result;
