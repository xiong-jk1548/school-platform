-- ============================================================
-- 班级检查扣分 —— 项目基础分
-- ============================================================
-- 升级时执行（已部署过的库可重跑，幂等）
-- ============================================================

ALTER TABLE public.inspection_categories
  ADD COLUMN IF NOT EXISTS base_score NUMERIC(5,2) NOT NULL DEFAULT 1;

-- 给已有的默认 8 项预填基础分（教室卫生 2 分，其他 1 分）
UPDATE public.inspection_categories
   SET base_score = CASE
     WHEN name = '教室卫生' THEN 2
     ELSE 1
   END
 WHERE school_id IN (SELECT id FROM public.schools)
   AND base_score = 1
   AND name IN ('教室卫生','包干区','课间操','眼保健操','仪容仪表','安全','出勤','其他');

COMMENT ON COLUMN public.inspection_categories.base_score IS '该项满分（基础分）；实际得分 = 基础分 + 加减分（score）';

-- ------------------------------------------------------------
-- 首次部署：为尚未配置检查项目的学校写入默认 8 项
-- 幂等：同名项目已存在则跳过（ON CONFLICT DO NOTHING）
-- 校长日后可在「班级检查扣分 → 管理检查项目」中自行增删改
-- ------------------------------------------------------------
INSERT INTO public.inspection_categories (school_id, name, sort_order, base_score, is_active)
SELECT s.id, d.name, d.sort_order, d.base_score, true
FROM public.schools s
CROSS JOIN (VALUES
    ('教室卫生', 0, 2.00::numeric),
    ('包干区',   1, 1.00::numeric),
    ('课间操',   2, 1.00::numeric),
    ('眼保健操', 3, 1.00::numeric),
    ('仪容仪表', 4, 1.00::numeric),
    ('安全',     5, 1.00::numeric),
    ('出勤',     6, 1.00::numeric),
    ('其他',     7, 1.00::numeric)
) AS d(name, sort_order, base_score)
ON CONFLICT (school_id, name) DO NOTHING;
