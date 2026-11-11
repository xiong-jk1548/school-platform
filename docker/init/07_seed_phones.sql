-- ============================================================
-- 给 4 个种子账号补 phone（用于手机号登录）
--
-- 注意：只补号码还不够。gotrue 会校验 phone_confirmed_at 非空，
--       否则密码正确也会返回 "Phone not confirmed"；
--       那个字段由 08_fix_seed_auth.sql 负责，本文件只补号码与相关元数据。
-- 幂等：可重复执行
-- ============================================================
UPDATE auth.users SET phone = '13800000001' WHERE email = 'admin@demo.com';
UPDATE auth.users SET phone = '13800000002' WHERE email = 'school_admin@demo.com';
UPDATE auth.users SET phone = '13800000003' WHERE email = 'teacher@demo.com';
UPDATE auth.users SET phone = '13800000004' WHERE email = 'teacher2@demo.com';

-- 同步 user_metadata.phone
UPDATE auth.users SET raw_user_meta_data = jsonb_set(COALESCE(raw_user_meta_data, '{}'::jsonb), '{phone}', to_jsonb(phone)) WHERE phone IS NOT NULL AND phone != '';

-- 同步 profiles.phone
UPDATE public.profiles p SET phone = u.phone FROM auth.users u WHERE p.id = u.id AND u.phone IS NOT NULL AND u.phone != '';

SELECT email, phone FROM auth.users WHERE email IN ('admin@demo.com','school_admin@demo.com','teacher@demo.com','teacher2@demo.com');
