-- ============================================================
-- 借阅模块表结构合并（存量库补列）+ 清理重复索引
-- ============================================================
-- 背景
--   homework_subjects / homework_records / borrow_items / borrow_records 四张表
--   历史上在 01_schema.sql 与 02_features_v2.sql 中被各建了一次，且列名不同。
--   因两边都是 CREATE TABLE IF NOT EXISTS，而 01 先执行，实际生效的一直是 01 那一版。
--   02 号里那套旧定义（total_qty / borrow_time / BIGSERIAL 主键等）从未生效，
--   但它的**索引**和**触发器**是真建了的，于是在库里留下两处不一致：
--
--   1) 重复索引：01 建 idx_hw_records_class_date / idx_borrow_records_item，
--      02 又建了同列的 idx_hw_record_class_date / idx_borrow_record_item；
--   2) 触发器错列：fn_update_borrow_available() 按旧列名写成 available_qty / NEW.qty，
--      而实际列叫 available_quantity、且当时根本没有 qty 列 ——
--      结果是**每一次借出登记都直接报错**（column "available_qty" does not exist），
--      借阅功能从未成功写入过一条记录（borrow_records 长期为 0 行）。
--
--   同时前端「物品台账 / 借阅登记」页一直在写这几个当时并不存在的列：
--      borrow_items.location、borrow_records.qty、borrow_records.return_time、
--      borrow_records.operator_user_id、borrow_records.expected_return_date
--   （SQL 里当时写的是 expect_return_date，与前端差一个字母，同样导致写入失败）。
--
-- 本脚本做什么
--   把存量库的结构收敛到 01_schema.sql 那一版（01 已是唯一权威定义）：
--     ① 补列：borrow_items.location / borrow_records.qty·return_time·operator_user_id
--     ② 改名：borrow_records.expect_return_date → expected_return_date
--     ③ 删掉 02 号遗留的重复索引
--     ④ 补 borrow_items 可用数量非负的 CHECK 约束
--
--   触发器函数 fn_update_borrow_available() 的修正体在 02_features_v2.sql 中维护
--   （该文件在本次部署中先于本脚本执行，CREATE OR REPLACE 会就地更新函数体，
--    触发器按函数名绑定，无需重建）。
--
-- 幂等：全部带存在性判断，可重复执行；对全新库执行时本脚本全部为空操作。
-- 执行：docker exec -i supabase-db psql -U supabase -d postgres < 14_borrow_schema_merge.sql
-- ============================================================

-- ------------------------------------------------------------
-- ① 补列
-- ------------------------------------------------------------
ALTER TABLE public.borrow_items ADD COLUMN IF NOT EXISTS location TEXT;

ALTER TABLE public.borrow_records ADD COLUMN IF NOT EXISTS qty INT NOT NULL DEFAULT 1;
ALTER TABLE public.borrow_records ADD COLUMN IF NOT EXISTS return_time TIMESTAMPTZ;
ALTER TABLE public.borrow_records ADD COLUMN IF NOT EXISTS operator_user_id UUID REFERENCES auth.users(id);

COMMENT ON COLUMN public.borrow_items.location IS '存放位置（物品台账可填，可为空）';
COMMENT ON COLUMN public.borrow_records.qty IS '本次借出数量（可一次借出多件），可用数量由触发器按此增减';
COMMENT ON COLUMN public.borrow_records.return_time IS '归还时刻（精确到分钟；actual_return_date 只到日）';
COMMENT ON COLUMN public.borrow_records.operator_user_id IS '经办教师（auth.users.id）';

-- ------------------------------------------------------------
-- ② 列改名的兼容处理
--    仅当"旧列在、新列不在"时才改名；新库（01 已用新列名）不会走到这里。
-- ------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'borrow_records'
                  AND column_name = 'expect_return_date')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'borrow_records'
                  AND column_name = 'expected_return_date')
    THEN
        ALTER TABLE public.borrow_records RENAME COLUMN expect_return_date TO expected_return_date;
        RAISE NOTICE 'borrow_records.expect_return_date 已改名为 expected_return_date';
    END IF;
END
$$;

-- ------------------------------------------------------------
-- ③ 清理 02 号遗留的重复索引（与 01 号同列不同名）
--    idx_hw_records_class_date (class_id, record_date)   ←→  idx_hw_record_class_date
--    idx_borrow_records_item   (item_id)                 ←→  idx_borrow_record_item
--    保留 01 号那一套（idx_hw_records_class_date / idx_borrow_records_item）。
-- ------------------------------------------------------------
DROP INDEX IF EXISTS public.idx_hw_record_class_date;
DROP INDEX IF EXISTS public.idx_borrow_record_item;

-- ------------------------------------------------------------
-- ④ 可用数量非负约束
--    不加"available_quantity <= total_quantity"：物品尚有借出时若把总数调小，
--    前端按差额同步会把可用数量截断到 0，随后归还回补就可能超过总数而误报约束冲突。
-- ------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'borrow_items_available_qty_check'
                      AND conrelid = 'public.borrow_items'::regclass)
    THEN
        ALTER TABLE public.borrow_items
            ADD CONSTRAINT borrow_items_available_qty_check CHECK (available_quantity >= 0);
    END IF;
END
$$;
