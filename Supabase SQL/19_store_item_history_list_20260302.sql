-- =========================================
-- 19 · store_item_history_list 商品库存变动历史汇总表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        03_user_list (user_id FK)
--        06_mother_inventory_list (unique_id FK)
-- 被依赖: 无
--
-- 汇总来自多个来源（交易、盘点、调拨、serialized 事件、采购等）的库存变动记录
-- 表内数据为冗余快照，仅用于客户端快速查询和展示商品历史
-- 不支持离线操作：由客户端在联网时从其他表同步写入
-- 一旦创建，不许更改、不许删除（触发器强制拦截 UPDATE 和 DELETE）

CREATE TABLE IF NOT EXISTS public.store_item_history_list (

  -- 全局自增主键，从 0 开始，由数据库分配
  history_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- 门店 ID
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 关联母表商品
  unique_id integer NOT NULL REFERENCES public.mother_inventory_list(unique_id),

  -- 库存数量变动
  -- 所有 inventory_mode 的商品都会记录：
  --   tracked    = 实际数量变化（正数入库，负数出库）
  --   serialized = 单件变动（+1 入库，-1 卖出等）
  --   untracked  = 交易时有数量；盘点时无论是否有变化，统一填 0
  -- 允许为 0（如盘点确认无变化、untracked 盘点档位调整等）
  qty_delta integer NOT NULL DEFAULT 0,

  -- 事件完成后的库存数量快照，由客户端填写
  -- tracked    = 当前库存数量
  -- serialized = 该 SKU 在该门店剩余的 in_stock 单件总数
  -- untracked  = 当前档位描述（如 "normal"、"few" 等）
  -- 纯展示用途，使用 text 类型兼容所有格式
  qty_snapshot text NOT NULL,

  -- 操作人
  user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- 事件发生时间（非系统生成），从来源表读取：
  --   交易         → transaction_line_list 对应交易的时间
  --   盘点         → store_inventory_adjustment_list 的时间
  --   调拨         → store_transfer_list 的时间
  --   serialized   → serialized_event_list 的 created_at
  --   采购         → purchase_order 的时间（未来）
  created_at timestamptz NOT NULL,

  -- 事件类型（由客户端填写）
  -- serialized 商品：读取 serialized_event_list 的 event_type
  --   如 'purchase', 'sell', 'return', 'store_transferred', 'repair_out' 等
  -- 非 serialized 商品：按来源填写
  --   如 'sale', 'refund', 'exchange', 'inventory_adjustment',
  --      'store_transfer', 'purchase_order' 等
  event_type text NOT NULL,

  -- 来源记录 ID（由客户端填写）
  -- 指向原始表的主键，使用 text 类型兼容 uuid 和 integer
  -- 如 transaction_line_list.line_id、adjustment_line_list.line_id、
  --    transfer_line_list.line_id、serialized_event_list.event_id 等
  source_id text NOT NULL
);

-- =========================================
-- 不可变触发器：拦截所有 UPDATE 和 DELETE
-- =========================================
CREATE OR REPLACE FUNCTION public.store_item_history_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'store_item_history_list is immutable: % is not allowed', TG_OP;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_store_item_history_no_update ON public.store_item_history_list;
CREATE TRIGGER trg_store_item_history_no_update
BEFORE UPDATE ON public.store_item_history_list
FOR EACH ROW
EXECUTE FUNCTION public.store_item_history_immutable();

DROP TRIGGER IF EXISTS trg_store_item_history_no_delete ON public.store_item_history_list;
CREATE TRIGGER trg_store_item_history_no_delete
BEFORE DELETE ON public.store_item_history_list
FOR EACH ROW
EXECUTE FUNCTION public.store_item_history_immutable();

-- =========================================
-- 索引
-- =========================================

-- 核心查询：某门店某商品的完整历史（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_item_history_store_item
  ON public.store_item_history_list (store_id, unique_id, created_at DESC);

-- 查询门店的所有库存变动
CREATE INDEX IF NOT EXISTS idx_item_history_store
  ON public.store_item_history_list (store_id, created_at DESC);

-- 查询商品在所有门店的变动历史
CREATE INDEX IF NOT EXISTS idx_item_history_unique_id
  ON public.store_item_history_list (unique_id, created_at DESC);

-- 按事件类型过滤
CREATE INDEX IF NOT EXISTS idx_item_history_event_type
  ON public.store_item_history_list (event_type);
