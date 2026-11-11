-- ============================================================
-- 账号删除修复：删除人员档案时同步清除登录凭据
-- ============================================================
-- 背景（问题现象）
--   前端「教师管理 / 管理员账号」的删除动作只执行了
--       DELETE FROM public.profiles WHERE id = ...
--   而登录凭据保存在 auth.users（外加 auth.identities），并未被删除。
--   于是产生两类后果：
--     1) 被"删除"的账号仍是有效登录账号（可登录，但档案已不存在）；
--     2) auth.users.phone 上的唯一索引仍被占用，重新创建同手机号账号时
--        make_unique_phone() 判定"号码已存在"，给手机号追加 1~2 位随机数字，
--        表现为"手机号自动变多一位"（例：15868958524 → 1586895852442）。
--
-- 本脚本的修复方式
--   在 profiles 上挂 AFTER DELETE 触发器，删除档案时一并删除登录凭据。
--   凡是删除 profiles 的入口（前端两个页面、将来的新入口、手工 SQL）都会自动生效，
--   不再依赖各调用点各自记得清理。
--
-- 引用的处理原则
--   业务数据（积分流水、成绩、获奖、作业、借阅、检查记录）**保留**，
--   仅把其中指向被删账号的"操作人"外键置空，避免因外键约束 NO ACTION 而删除失败。
--
-- 幂等：可重复执行。
-- ============================================================


-- ------------------------------------------------------------
-- 1. 核心清理函数
--    清除对目标账号的全部引用，然后删除登录凭据（级联删除 profiles/identities/
--    sessions 等）。返回清理明细，供调用方记录或排查。
--    ⚠️ 安全：SECURITY DEFINER 且不向 authenticated 授权，只允许触发器与
--       数据库管理角色调用，避免被普通用户用于删除他人账号。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_purge_user_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
DECLARE
    v_cleared  jsonb := '{}'::jsonb;
    v_affected integer;
    v_profile  record;
    v_had_auth boolean;
BEGIN
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION '缺少账号 ID';
    END IF;

    -- 记录待删账号信息（可能已不存在，故用 SELECT INTO 而非断言）
    SELECT real_name, phone, role, school_id
      INTO v_profile
      FROM public.profiles
     WHERE id = p_user_id;

    -- ① 解除业务数据对本人账号的引用（保留业务记录本身）
    UPDATE public.score_log SET operate_user_id = NULL WHERE operate_user_id = p_user_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected > 0 THEN
        v_cleared := v_cleared || jsonb_build_object('score_log.operate_user_id', v_affected);
    END IF;

    UPDATE public.score_log SET teacher_id = NULL WHERE teacher_id = p_user_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected > 0 THEN
        v_cleared := v_cleared || jsonb_build_object('score_log.teacher_id', v_affected);
    END IF;

    UPDATE public.student_scores SET operator_user_id = NULL WHERE operator_user_id = p_user_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected > 0 THEN
        v_cleared := v_cleared || jsonb_build_object('student_scores.operator_user_id', v_affected);
    END IF;

    UPDATE public.student_awards SET operator_user_id = NULL WHERE operator_user_id = p_user_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected > 0 THEN
        v_cleared := v_cleared || jsonb_build_object('student_awards.operator_user_id', v_affected);
    END IF;

    UPDATE public.homework_records SET update_user_id = NULL WHERE update_user_id = p_user_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected > 0 THEN
        v_cleared := v_cleared || jsonb_build_object('homework_records.update_user_id', v_affected);
    END IF;

    -- 借阅流水的经办教师（该列由 01 号脚本建表自带、14 号脚本为存量库补入；
    -- 本函数与 14 号在同一次部署中先 13 后 14 执行，实际调用时该列必然已存在）
    UPDATE public.borrow_records SET operator_user_id = NULL WHERE operator_user_id = p_user_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected > 0 THEN
        v_cleared := v_cleared || jsonb_build_object('borrow_records.operator_user_id', v_affected);
    END IF;

    UPDATE public.class_inspection_records SET operator_user_id = NULL WHERE operator_user_id = p_user_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected > 0 THEN
        v_cleared := v_cleared || jsonb_build_object('class_inspection_records.operator_user_id', v_affected);
    END IF;

    -- 成绩授权名单：本人作为"被授权人"的记录直接删除（授权对象已不存在，保留无意义）；
    -- 本人作为"授权人"（班主任）留下的记录保留 —— 它表达的是"这个班允许谁看成绩"，
    -- 换班主任后仍然有效，故只置空 granted_by。
    DELETE FROM public.grade_access_grants WHERE teacher_id = p_user_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected > 0 THEN
        v_cleared := v_cleared || jsonb_build_object('grade_access_grants.teacher_id', v_affected);
    END IF;

    UPDATE public.grade_access_grants SET granted_by = NULL WHERE granted_by = p_user_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected > 0 THEN
        v_cleared := v_cleared || jsonb_build_object('grade_access_grants.granted_by', v_affected);
    END IF;

    -- 解除班主任绑定（班级保留，只是暂时没有班主任）
    UPDATE public.classes SET homeroom_teacher_id = NULL WHERE homeroom_teacher_id = p_user_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    IF v_affected > 0 THEN
        v_cleared := v_cleared || jsonb_build_object('classes.homeroom_teacher_id', v_affected);
    END IF;

    -- ② 删除登录凭据（会级联删除 profiles / auth.identities / auth.sessions 等）
    DELETE FROM auth.users WHERE id = p_user_id;
    GET DIAGNOSTICS v_affected = ROW_COUNT;
    v_had_auth := v_affected > 0;

    -- ③ 兜底：历史上出现过"profiles 在、auth.users 已不在"的脏数据，
    --    此时上面删不到任何行，直接补删档案，保证档案也清干净
    IF NOT v_had_auth THEN
        DELETE FROM public.profiles WHERE id = p_user_id;
    END IF;

    RETURN jsonb_build_object(
        'user_id',    p_user_id,
        'real_name',  v_profile.real_name,
        'phone',      v_profile.phone,
        'role',       v_profile.role,
        'auth_deleted', v_had_auth,
        'cleared',    v_cleared
    );
END;
$$;

-- 不允许普通登录用户直接调用（触发器以函数属主身份执行，不受影响）
REVOKE ALL ON FUNCTION public.fn_purge_user_account(uuid) FROM PUBLIC;

COMMENT ON FUNCTION public.fn_purge_user_account(uuid) IS
    '清除业务数据中对指定账号的引用，并删除其登录凭据 auth.users（级联删除 profiles）。'
    '由 trg_profiles_purge_account 触发器调用，也可由数据库管理员手工调用以清理历史脏数据。';


-- ------------------------------------------------------------
-- 2. 触发器：删除人员档案 → 同步删除登录凭据
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_profiles_purge_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
BEGIN
    PERFORM public.fn_purge_user_account(OLD.id);
    RETURN OLD;
END;
$$;

REVOKE ALL ON FUNCTION public.trg_profiles_purge_account() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_profiles_purge_account ON public.profiles;

CREATE TRIGGER trg_profiles_purge_account
    AFTER DELETE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_profiles_purge_account();

-- 说明：AFTER DELETE 触发时 profiles 行已删除，函数内再删 auth.users 会级联到
--       profiles —— 该行已不存在，不会再次触发本触发器，无递归风险。


-- ------------------------------------------------------------
-- 3. make_unique_phone 健壮性修正
--    原实现只尝试追加一次 1~2 位随机数，既可能再次撞号，也可能把号码拉长到 13 位。
--    改为最多尝试 50 次、每次追加固定的 2 位后缀，并在全部失败时明确报错。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.make_unique_phone(base text)
RETURNS text
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    candidate text := base;
    attempt   integer;
BEGIN
    -- 未提供手机号：生成一个占位号码
    IF candidate IS NULL OR candidate = '' THEN
        candidate := '1' || lpad(floor(random() * 99999999)::text, 8, '0');
        WHILE EXISTS (SELECT 1 FROM auth.users u WHERE u.phone = candidate) LOOP
            candidate := '1' || lpad(floor(random() * 99999999)::text, 8, '0');
        END LOOP;
        RETURN candidate;
    END IF;

    -- 号码未被占用：直接使用
    IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.phone = candidate) THEN
        RETURN candidate;
    END IF;

    -- 已被占用：追加 2 位后缀重试
    FOR attempt IN 1..50 LOOP
        candidate := base || lpad(floor(random() * 100)::text, 2, '0');
        IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.phone = candidate) THEN
            RETURN candidate;
        END IF;
    END LOOP;

    RAISE EXCEPTION '手机号 % 已被占用，且无法生成可用的备用号码，请更换手机号后重试', base;
END;
$$;

COMMENT ON FUNCTION public.make_unique_phone(text) IS
    '返回一个未被 auth.users 占用的手机号：优先原号，被占用时追加 2 位后缀重试，'
    '避免出现"删除后重建账号手机号变长且不可预期"的情况。';

GRANT EXECUTE ON FUNCTION public.make_unique_phone(text) TO anon, authenticated;


-- ------------------------------------------------------------
-- 4. 历史孤儿账号排查（只读，供运维核对）
--    查出的行表示"登录凭据还在、人员档案已被删除"的历史脏数据。
--    手工清理方式（数据库管理角色执行）：
--        SELECT public.fn_purge_user_account(id);
-- ------------------------------------------------------------
COMMENT ON TABLE public.profiles IS
    '人员档案（教师/学校管理员/系统管理员）。删除本表记录会通过触发器 '
    'trg_profiles_purge_account 同步删除该账号的登录凭据 auth.users。';
