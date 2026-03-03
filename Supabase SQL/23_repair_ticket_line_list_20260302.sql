-- Async requirement: YES - offline POS must continue high-frequency essential operations using local snapshot; sync changes to cloud after reconnection.
-- 异步需求：是 - POS 离线时需依赖本地快照继续高频必要操作，网络恢复后将变更同步到云端。
-- =========================================
-- 23 · repair_ticket_line_list 修理工单明细表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        06_mother_inventory_list (unique_id FK)
--        22_repair_ticket_list (repair_ticket_id FK)
-- 被依赖: 无
--
-- 每行代表一个修理项目 / issue

CREATE TABLE IF NOT EXISTS public.repair_ticket_line_list (

  -- 客户端生成 UUIDv7
  repair_ticket_line_id uuid PRIMARY KEY,

  -- 所属工单
  repair_ticket_id uuid NOT NULL REFERENCES public.repair_ticket_list(repair_ticket_id),

  -- 门店（冗余，方便离线同步按门店筛选）
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 关联母表商品（可选，手动录入项目时为 NULL）
  unique_id int4 REFERENCES public.mother_inventory_list(unique_id),

  -- 项目名称（快照 / 手动录入）
  item_name text NOT NULL,

  -- 数量
  qty int4 NOT NULL DEFAULT 1 CHECK (qty > 0),

  -- 成本与售价，允许后续补填
  unit_cost numeric(10,2),
  unit_price numeric(10,2),

  -- 备注
  note text,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  synced_at timestamptz
);

-- =========================================
-- 索引
-- =========================================

-- 查某工单的所有明细行
CREATE INDEX IF NOT EXISTS idx_repair_ticket_line_ticket
  ON public.repair_ticket_line_list (repair_ticket_id)
  WHERE deleted_at IS NULL;

-- 查某商品的修理使用历史
CREATE INDEX IF NOT EXISTS idx_repair_ticket_line_unique_id
  ON public.repair_ticket_line_list (unique_id)
  WHERE unique_id IS NOT NULL AND deleted_at IS NULL;

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_repair_ticket_line_set_updated_at ON public.repair_ticket_line_list;
CREATE TRIGGER trg_repair_ticket_line_set_updated_at
BEFORE UPDATE ON public.repair_ticket_line_list
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
