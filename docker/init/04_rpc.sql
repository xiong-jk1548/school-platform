-- ============================================================
-- 完整业务 RPC 集合（修复版）
-- 自动处理 phone/email 重复，前端可以直接调
--
-- 背景：前端自己 INSERT auth.users 时 phone/email 撞库会直接 409，
--       而手动构造的 identities / token 字段又很容易漏（漏一项就登录失败），
--       所以把"建账号"整体下沉成数据库 RPC。
-- 调用约定：前端用 supabase.rpc('<函数名>', { p_xxx: ... }) 传参，
--           对象键就是下面声明的 p_* 参数名，改名会直接打断前端调用。
-- ============================================================

DROP FUNCTION IF EXISTS public.create_school_admin(text,text,text,text,uuid);
DROP FUNCTION IF EXISTS public.create_teacher(text,text,text,text,uuid,uuid);

-- ============ 通用工具：造一个不撞 auth.users 唯一约束的 phone / email ============
-- 坑：auth.users 的 phone / email 上有唯一约束，批量建号撞号会让接口直接 409，
--     所以下面两个函数在写入前先探测、再改写成不存在的值。

-- make_unique_phone(base) RETURNS text
--   空值        -> 随机生成 '1' + 8 位数字
--   已存在      -> 末尾追加 0~98 的随机数
-- @param base 期望使用的手机号，可为 NULL 或空串
-- @return 一个当前 auth.users 中不存在的手机号
-- @note 标 STABLE：函数体内读了 auth.users，不能声明成 IMMUTABLE
CREATE OR REPLACE FUNCTION public.make_unique_phone(base text) RETURNS text AS $$
DECLARE
  phone_candidate text := base;
BEGIN
  IF phone_candidate IS NULL OR phone_candidate = '' THEN
    phone_candidate := '1' || lpad(floor(random() * 99999999)::text, 8, '0');
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users u WHERE u.phone = phone_candidate) THEN
    phone_candidate := phone_candidate || floor(random() * 99)::text;
  END IF;
  RETURN phone_candidate;
END;
$$ LANGUAGE plpgsql STABLE;

-- make_unique_email(base, fallback_prefix) RETURNS text
--   空值        -> <prefix>_<8位随机>@local.lan
--   已存在      -> 在 @ 前插入 6 位随机串
-- @param base 期望使用的邮箱，可为 NULL 或空串
-- @param fallback_prefix 邮箱缺失时生成的本地部分前缀，默认 'user'
-- @return 一个当前 auth.users 中不存在的邮箱
CREATE OR REPLACE FUNCTION public.make_unique_email(base text, fallback_prefix text DEFAULT 'user') RETURNS text AS $$
DECLARE
  email_candidate text := base;
  random_suffix text;
BEGIN
  IF email_candidate IS NULL OR email_candidate = '' THEN
    random_suffix := substring(md5(random()::text) FROM 1 FOR 8);
    email_candidate := fallback_prefix || '_' || random_suffix || '@local.lan';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users u WHERE u.email = email_candidate) THEN
    random_suffix := substring(md5(random()::text) FROM 1 FOR 6);
    email_candidate := split_part(email_candidate, '@', 1) || '_' || random_suffix || '@' || split_part(email_candidate, '@', 2);
  END IF;
  RETURN email_candidate;
END;
$$ LANGUAGE plpgsql STABLE;

GRANT EXECUTE ON FUNCTION public.make_unique_phone(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.make_unique_email(text, text) TO anon, authenticated;

-- ==================== 创建学校管理员 ====================
-- create_school_admin(p_phone, p_password, p_real_name, p_email, p_school_id) RETURNS jsonb
-- 一步建出"能直接登录"的学校管理员：auth.users + auth.identities + public.profiles 三张表一起写。
-- @param p_phone     手机号，撞库时自动改写
-- @param p_password  明文密码，入库前 bcrypt 加密；为空直接 RAISE EXCEPTION
-- @param p_real_name 真实姓名
-- @param p_email     邮箱，可空；为空时按 p_phone 生成 @local.lan 兜底邮箱
-- @param p_school_id 所属学校，同时写进 raw_user_meta_data 供前端 store 与 RLS 读取
-- @return jsonb { user_id, email, phone }，即实际落库的账号信息（可能已被去重改写）
-- @note 参数名与前端 supabase.rpc(name, {...}) 的对象键一一对应，改名会直接打断调用
-- @note SECURITY DEFINER + search_path=auth,public：为了有权限写 auth 模式下的表；
--       token 类字段一律给空串而不是 NULL，否则 gotrue 扫描时会报
--       "converting NULL to string is unsupported"
-- ====================
CREATE OR REPLACE FUNCTION public.create_school_admin(
  p_phone text,
  p_password text,
  p_real_name text,
  p_email text DEFAULT NULL,
  p_school_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
DECLARE
  v_user_id uuid;
  v_email text;
  v_phone text;
BEGIN
  v_phone := public.make_unique_phone(p_phone);
  v_email := public.make_unique_email(p_email, COALESCE(p_phone, 'admin'));

  IF p_password IS NULL OR p_password = '' THEN
    RAISE EXCEPTION '密码不能为空';
  END IF;

  v_user_id := gen_random_uuid();

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, phone,
    encrypted_password, raw_user_meta_data, raw_app_meta_data,
    email_confirmed_at, phone_confirmed_at,
    confirmation_token, recovery_token,
    email_change_token_new, email_change,
    phone_change, phone_change_token,
    reauthentication_token,
    created_at, updated_at,
    invited_at, confirmation_sent_at,
    recovery_sent_at, email_change_sent_at,
    phone_change_sent_at, reauthentication_sent_at,
    banned_until
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    v_email, v_phone,
    crypt(p_password, gen_salt('bf')),
    jsonb_build_object('role','school_admin','real_name',p_real_name,'school_id',p_school_id),
    jsonb_build_object('provider','email','providers',array['email']),
    now(), now(), '', '', '', '', '', '', '',
    now(), now(), now(), now(), now(), now(), now(), now(), NULL
  );

  INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES (
    v_user_id, v_user_id, v_email,
    jsonb_build_object('email', v_email), 'email',
    now(), now(), now()
  );

  INSERT INTO public.profiles (
    id, role, school_id, real_name, name, email, phone, status, create_time, created_at
  ) VALUES (
    v_user_id, 'school_admin', p_school_id, p_real_name, p_real_name, v_email, v_phone,
    'active', now(), now()
  );

  RETURN jsonb_build_object('user_id', v_user_id, 'email', v_email, 'phone', v_phone);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_school_admin(text, text, text, text, uuid) TO anon, authenticated;

-- ==================== 创建教师 ====================
-- create_teacher(p_phone, p_password, p_real_name, p_email, p_school_id, p_class_id) RETURNS jsonb
-- 与 create_school_admin 同构，额外把班级绑定写进 profiles（class_id / class_name）与 user_metadata。
-- @param p_phone     手机号，撞库时自动改写
-- @param p_password  明文密码，入库前 bcrypt 加密；为空直接 RAISE EXCEPTION
-- @param p_real_name 真实姓名
-- @param p_email     邮箱，可空；为空时按 p_phone 生成 @local.lan 兜底邮箱
-- @param p_school_id 所属学校
-- @param p_class_id  绑定班级，可空；非空时回查 classes 取班级名一并写入
-- @return jsonb { user_id, email, phone }，即实际落库的账号信息（可能已被去重改写）
-- @note 参数名与前端 supabase.rpc(name, {...}) 的对象键一一对应，改名会直接打断调用
-- ====================
CREATE OR REPLACE FUNCTION public.create_teacher(
  p_phone text,
  p_password text,
  p_real_name text,
  p_email text DEFAULT NULL,
  p_school_id uuid DEFAULT NULL,
  p_class_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
DECLARE
  v_user_id uuid;
  v_email text;
  v_phone text;
  v_class_name text;
BEGIN
  v_phone := public.make_unique_phone(p_phone);
  v_email := public.make_unique_email(p_email, COALESCE(p_phone, 'teacher'));

  IF p_password IS NULL OR p_password = '' THEN
    RAISE EXCEPTION '密码不能为空';
  END IF;

  IF p_class_id IS NOT NULL THEN
    SELECT class_name INTO v_class_name FROM public.classes WHERE id = p_class_id;
  END IF;

  v_user_id := gen_random_uuid();

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, phone,
    encrypted_password, raw_user_meta_data, raw_app_meta_data,
    email_confirmed_at, phone_confirmed_at,
    confirmation_token, recovery_token,
    email_change_token_new, email_change,
    phone_change, phone_change_token,
    reauthentication_token,
    created_at, updated_at,
    invited_at, confirmation_sent_at,
    recovery_sent_at, email_change_sent_at,
    phone_change_sent_at, reauthentication_sent_at,
    banned_until
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    v_email, v_phone,
    crypt(p_password, gen_salt('bf')),
    jsonb_build_object('role','teacher','real_name',p_real_name,'school_id',p_school_id,'class_id',p_class_id),
    jsonb_build_object('provider','email','providers',array['email']),
    now(), now(), '', '', '', '', '', '', '',
    now(), now(), now(), now(), now(), now(), now(), now(), NULL
  );

  INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES (
    v_user_id, v_user_id, v_email,
    jsonb_build_object('email', v_email), 'email',
    now(), now(), now()
  );

  INSERT INTO public.profiles (
    id, role, school_id, class_id, class_name, real_name, name, email, phone, status, create_time, created_at
  ) VALUES (
    v_user_id, 'teacher', p_school_id, p_class_id, v_class_name,
    p_real_name, p_real_name, v_email, v_phone,
    'active', now(), now()
  );

  RETURN jsonb_build_object('user_id', v_user_id, 'email', v_email, 'phone', v_phone);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_teacher(text, text, text, text, uuid, uuid) TO anon, authenticated;

-- 验证
SELECT proname, prosrc IS NOT NULL AS has_body FROM pg_proc
JOIN pg_namespace n ON n.oid = pronamespace
WHERE n.nspname='public' AND proname IN ('create_school_admin','create_teacher','make_unique_phone','make_unique_email');
