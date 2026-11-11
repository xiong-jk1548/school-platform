-- ============================================================
-- V2 增量脚本 —— 作业管理 + 物品借阅（补充索引与借阅触发器）
-- ============================================================
-- 【本次清理说明】
--   本文件原先重复 CREATE 了以下四张表，且列名与 01_schema.sql 中的版本不一致：
--       homework_subjects  : subject_name/name vs subject_name（缺 name、created_at）
--       homework_records   : 缺 create_time / created_at
--       borrow_items       : total_qty/available_qty/location vs total_quantity/available_quantity
--       borrow_records     : BIGSERIAL 主键、qty/borrow_time/return_time vs UUID 主键、borrow_date
--   两边都是 CREATE TABLE IF NOT EXISTS，而 01_schema.sql 按文件名顺序先执行，
--   所以实际生效的一直是 01 那一版 —— 本文件的建表语句属于永远不生效的死代码，
--   却让人误以为库里存在"第二套列"。现以 01_schema.sql 为唯一权威定义，删除重复建表。
--
--   同时删除的还有这四张表的 RLS 策略：09_school_isolation_rls.sql 开头有一个 DO 块，
--   会把所有"USING 子句里查询过 profiles"的旧策略一次性 DROP（避免策略自引用触发
--   "infinite recursion detected in policy"）。因此这里的策略建完就会被删掉，
--   只留下"建了又删"的噪声。这四张表的 RLS 统一由 09 号脚本定义。
--
-- 本文件现在只保留两样 01_schema.sql 未覆盖的内容：
--   1. 补充索引
--   2. 借阅可用数量维护触发器
--
-- 全部使用 IF NOT EXISTS / CREATE OR REPLACE，可重复安全重跑
-- 执行方式：
--   docker exec -i supabase-db psql -U supabase -d postgres < 02_features_v2.sql
-- ============================================================

-- ---------------------- 模块一：作业完成情况管理 ----------------------
-- 表结构见 01_schema.sql 第 6~8 节：
--   homework_subjects（科目配置） / homework_records（每生每科每天完成情况） / homework_notes（当日作业内容）

-- 科目表按学校查询的支撑索引
CREATE INDEX IF NOT EXISTS idx_hw_subject_school ON public.homework_subjects(school_id);

-- 作业完成记录按学生查询
-- （按班级+日期查询的索引已在 01_schema.sql 中建为 idx_hw_records_class_date）
CREATE INDEX IF NOT EXISTS idx_hw_record_student ON public.homework_records(student_id);

-- ---------------------- 模块二：班级公共物品借阅登记 ----------------------
-- 表结构见 01_schema.sql 第 9~10 节：
--   borrow_items（班级物品台账） / borrow_records（借还流水）

-- 物品台账按班级查询
CREATE INDEX IF NOT EXISTS idx_borrow_item_class ON public.borrow_items(class_id);

-- 借阅流水按学生 / 按班级查询
-- （按物品查询的索引已在 01_schema.sql 中建为 idx_borrow_records_item）
CREATE INDEX IF NOT EXISTS idx_borrow_record_student ON public.borrow_records(student_id);
CREATE INDEX IF NOT EXISTS idx_borrow_record_class   ON public.borrow_records(class_id);

-- 物品可用数量自动维护触发器
--   借出：INSERT status='borrowed'             → available_quantity -= qty
--   归还：UPDATE status 由 borrowed 改为 returned → available_quantity += qty
--
-- 【列名变更记录】本函数曾误用 02 版旧列名 available_qty / NEW.qty，而运行库里的列
--   实际叫 available_quantity、且借阅记录里当时根本没有 qty 列，导致每一次借出登记都抛
--   "ERROR: column \"available_qty\" does not exist"，借阅功能从未成功写入过一条记录
--   （borrow_records 长期为 0 行）。现改为与 01_schema.sql 一致的列名。
CREATE OR REPLACE FUNCTION public.fn_update_borrow_available()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'borrowed' THEN
        UPDATE public.borrow_items SET available_quantity = available_quantity - NEW.qty
        WHERE id = NEW.item_id AND available_quantity >= NEW.qty;
    ELSIF TG_OP = 'UPDATE' AND OLD.status = 'borrowed' AND NEW.status = 'returned' THEN
        UPDATE public.borrow_items SET available_quantity = available_quantity + NEW.qty
        WHERE id = NEW.item_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_borrow_record_change ON public.borrow_records;
CREATE TRIGGER trg_borrow_record_change
AFTER INSERT OR UPDATE OF status ON public.borrow_records
FOR EACH ROW EXECUTE FUNCTION public.fn_update_borrow_available();
