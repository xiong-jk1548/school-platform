-- ============================================================
-- 15_profile_metadata_sync.sql
-- 档案（public.profiles）→ 登录元数据（auth.users.raw_user_meta_data）自动同步
--
-- 背景（真实故障）：
--   后端 RLS 策略与前端 user store 都以 JWT 里的 user_metadata.class_id /
--   school_id / role 作为隔离基准。而"班级管理"里设置或解除班主任，只会更新
--   public.profiles.class_id，auth.users 里的元数据不会跟着动 → 教师下次登录
--   拿到的 JWT 仍是旧班级，与档案脱节。后果是前端按旧班过滤查不到数据、
--   写入被 RLS 拒绝（表现为：物品借阅列表空白、看不到归还入口；作业备注保存失败）。
--
-- 对策：在 profiles 上挂 AFTER UPDATE 触发器，关注列一变就同步元数据。
--   ⚠️ JWT 是登录时签发的快照，本触发器保证的是"数据层面不再长期漂移"；
--      改完班主任后教师需重新登录才能拿到新的 JWT。存量不一致由 08 号脚本修正
--      （部署顺序 08 → 15，正好先修数据再挂钩子）。
--
-- 幂等：可重复执行。
-- ============================================================

CREATE OR REPLACE FUNCTION public.trg_profiles_sync_metadata()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
BEGIN
    -- 精确覆盖（含置空）：教师被解除班主任时 class_id 必须一并清成 null。
    -- 这里刻意不用 jsonb_strip_nulls —— 那只会"补新键、不删旧键"，
    -- 会让 JWT 里永久残留上一个班级，正是本次故障的形态。
    UPDATE auth.users u
       SET raw_user_meta_data = COALESCE(u.raw_user_meta_data, '{}'::jsonb)
           || jsonb_build_object(
                  'role',       NEW.role,
                  'school_id',  NEW.school_id::text,
                  'class_id',   NEW.class_id::text,
                  'class_name', NEW.class_name
              )
     WHERE u.id = NEW.id;
    RETURN NEW;
EXCEPTION
    -- 元数据同步失败不得阻塞档案本身的更新（档案是业务真源，优先级更高），
    -- 但要留下 WARNING 便于排查
    WHEN OTHERS THEN
        RAISE WARNING 'trg_profiles_sync_metadata 同步失败 (profile=%): %', NEW.id, SQLERRM;
        RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_sync_metadata ON public.profiles;
CREATE TRIGGER trg_profiles_sync_metadata
    AFTER UPDATE OF class_id, class_name, role, school_id ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_profiles_sync_metadata();

-- ============================================================
-- 验证（改一位教师的班级后，auth 元数据应同步变化）：
--   UPDATE public.profiles SET class_id = NULL WHERE id = '<某教师 id>';
--   SELECT p.real_name, p.class_id,
--          u.raw_user_meta_data ->> 'class_id' AS auth_class_id
--     FROM public.profiles p JOIN auth.users u ON u.id = p.id
--    WHERE p.role = 'teacher';
-- ============================================================
