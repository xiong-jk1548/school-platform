-- ============================================================
-- 08_fix_seed_auth.sql
-- Idempotent fix for seed accounts created by direct INSERT into auth.users.
-- (GoTrue v2 requires: all-zero instance_id, a matching auth.identities row,
--  and non-NULL token columns, otherwise password login fails with
--  "converting NULL to string is unsupported" / "user not found".)
-- Safe to run multiple times.
--
-- 直插 auth.users 会让密码登录失败，而且是四层原因叠加，按下面顺序逐层修：
--   ① 缺 auth.identities 关联   -> 密码对也报 invalid_credentials
--   ② instance_id 是随机 UUID   -> gotrue 只认全零默认实例，查不到该用户
--   ③ confirmation_token 等列为 NULL -> 500 converting NULL to string is unsupported
--   ④ raw_user_meta_data 缺 role -> 登录提示成功但页面不跳转（前端 user store 按
--      user_metadata.role 决定首页，role 为空会被路由守卫静默踢回 /login）
-- 教训：新建用户永远优先走 signup / admin API，不要手动直插 auth.users；
--       已经直插的，按上面四条把缺的字段补齐即可。
-- ============================================================

-- 1) instance_id must be the default instance (all zeros), otherwise GoTrue
--    cannot find the user on password login.
UPDATE auth.users
SET instance_id = '00000000-0000-0000-0000-000000000000'
WHERE email IN (
    'admin@demo.com',
    'school_admin@demo.com',
    'teacher@demo.com',
    'teacher2@demo.com'
);

-- 2) Every email/password user needs one row in auth.identities (provider 'email'),
--    or login fails even with correct credentials.
INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
)
SELECT
    u.id, u.id, u.id,
    jsonb_build_object(
        'sub', u.id::text,
        'email', u.email,
        'email_verified', true,
        'phone_verified', false
    ),
    'email', now(), now(), now()
FROM auth.users u
WHERE u.email IN (
    'admin@demo.com',
    'school_admin@demo.com',
    'teacher@demo.com',
    'teacher2@demo.com'
)
  AND NOT EXISTS (
      SELECT 1 FROM auth.identities i WHERE i.user_id = u.id
  );

-- 3) Token / pending-change columns must not be NULL (GoTrue scanner reads
--    them into plain strings).
UPDATE auth.users
SET confirmation_token        = COALESCE(confirmation_token, ''),
    recovery_token            = COALESCE(recovery_token, ''),
    email_change_token_new    = COALESCE(email_change_token_new, ''),
    email_change_token_current= COALESCE(email_change_token_current, ''),
    email_change              = COALESCE(email_change, ''),
    phone                     = COALESCE(phone, ''),
    phone_change_token        = COALESCE(phone_change_token, ''),
    reauthentication_token    = COALESCE(reauthentication_token, '')
WHERE email IN (
    'admin@demo.com',
    'school_admin@demo.com',
    'teacher@demo.com',
    'teacher2@demo.com'
);

-- 3b) Mark phone as confirmed for any account that has a phone number;
--     otherwise gotrue v2 returns phone_not_confirmed even with right password.
UPDATE auth.users
SET phone_confirmed_at = COALESCE(phone_confirmed_at, now())
WHERE phone IS NOT NULL AND phone <> ''
  AND email IN (
    'admin@demo.com',
    'school_admin@demo.com',
    'teacher@demo.com',
    'teacher2@demo.com'
  );

-- 3c) Force all seed accounts to the unified password '123456' so every
--     test account shares the single password documented in the deploy notes.
--     Without this, dev's Admin@123 leaks into the deployment seed and
--     trips up first-time login on `admin@demo.com`.
UPDATE auth.users
SET encrypted_password = crypt('123456', gen_salt('bf')),
    email_confirmed_at = COALESCE(email_confirmed_at, now())
WHERE email IN (
    'admin@demo.com',
    'school_admin@demo.com',
    'teacher@demo.com',
    'teacher2@demo.com'
);

-- 4) Merge profile fields (role/name/school/class) into raw_user_meta_data.
--    The frontend user store reads user_metadata.role to resolve the home page
--    (roleHomeMap) after login; if it is missing, the router guard silently
--    kicks the user back to /login ("登录成功但页面不跳转、无报错").
--    Idempotent: re-merging overwrites the same keys with the same values.
UPDATE auth.users u
SET raw_user_meta_data = COALESCE(u.raw_user_meta_data, '{}'::jsonb)
    || jsonb_strip_nulls(jsonb_build_object(
        'role',       p.role,
        'name',       COALESCE(NULLIF(p.name, ''), NULLIF(p.real_name, ''), u.email),
        'school_id',  p.school_id::text,
        'class_id',   p.class_id::text,
        'class_name', p.class_name
    ))
FROM public.profiles p
WHERE p.id = u.id
  AND u.email IN (
    'admin@demo.com',
    'school_admin@demo.com',
    'teacher@demo.com',
    'teacher2@demo.com'
);
