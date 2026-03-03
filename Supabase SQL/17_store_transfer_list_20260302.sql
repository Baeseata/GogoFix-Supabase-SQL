-- =============================================
-- File 17 · store_transfer_list — Inter-store transfer header table
-- 文件 17 · store_transfer_list — 门店间调拨主表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list (store_id / target_store_id FK)
--   03_user_list  (created_by_user_id / confirmed_by_user_id FK)
-- Dependents / 被依赖:
--   18_store_transfer_line_list (store_transfer_id FK)
-- =============================================
-- Records inter-store inventory transfers. Supports tracked / untracked / serialized items.
-- Online-only (no synced_at field — transfers cannot be performed offline).
-- Workflow: source store creates the transfer → target store confirms receipt.
-- By design, only INSERT and confirmation UPDATEs are intended (no DELETE).
-- ─────────────────────────────────────────────
-- 记录门店间的库存调拨单。支持 tracked / untracked / serialized 商品。
-- 仅在联网时可操作，不支持离线。
-- 流程：发货门店创建调拨单 → 收货门店确认收货。
-- 设计上只允许 INSERT 和确认收货时的 UPDATE，不应删除。
-- =============================================

CREATE TABLE IF NOT EXISTS public.store_transfer_list (

  -- Auto-increment primary key, starting from 0
  -- 全局自增主键，从 0 开始
  store_transfer_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- Source store (sender), FK to store_list
  -- 调出门店（发货方），外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Target store (receiver), FK to store_list
  -- 调入门店（收货方），外键指向 store_list
  target_store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Employee who created the transfer, FK to user_list
  -- 创建调拨单的员工，外键指向 user_list
  created_by_user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- Employee who confirmed receipt; NULL = not yet confirmed (still in transit)
  -- 确认收货的员工；NULL 表示尚未确认（仍在途中）
  confirmed_by_user_id integer DEFAULT NULL REFERENCES public.user_list(user_id),

  -- Timestamp when receipt was confirmed; NULL = not yet confirmed
  -- confirmed_at and confirmed_by_user_id must both be NULL or both be set (see CHECK below)
  -- 确认收货的时间；NULL 表示尚未确认
  -- confirmed_at 和 confirmed_by_user_id 应同时为空或同时有值（见下方 CHECK）
  confirmed_at timestamptz DEFAULT NULL,

  -- Total cost of all items in this transfer (calculated by client)
  -- 调拨总成本（客户端计算后传入）
  cost_total numeric(10,2) NOT NULL DEFAULT 0,

  -- Total retail value of all items in this transfer (calculated by client)
  -- 调拨总零售价值（客户端计算后传入）
  price_total numeric(10,2) NOT NULL DEFAULT 0,

  -- Record creation timestamp
  -- 记录创建时间
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- CHECK: cannot transfer to yourself (source and target must be different stores)
  -- 约束：不能自己调给自己（发货方和收货方必须是不同门店）
  CONSTRAINT chk_store_transfer_list_not_self
    CHECK (store_id != target_store_id),

  -- CHECK: confirmation consistency — confirmed_by_user_id and confirmed_at must both be NULL or both be set
  -- 约束：确认状态一致性 — confirmed_by_user_id 和 confirmed_at 应同时为空或同时有值
  CONSTRAINT chk_store_transfer_list_confirm_consistency
    CHECK (
      (confirmed_by_user_id IS NULL AND confirmed_at IS NULL)
      OR
      (confirmed_by_user_id IS NOT NULL AND confirmed_at IS NOT NULL)
    )
);

-- =============================================
-- Indexes / 索引
-- =============================================

-- Look up transfers sent from a store (newest first)
-- 查询门店发出的调拨单（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_transfer_store
  ON public.store_transfer_list (store_id, created_at DESC);

-- Look up transfers received by a store (newest first)
-- 查询门店收到的调拨单（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_transfer_target_store
  ON public.store_transfer_list (target_store_id, created_at DESC);

-- Look up pending (unconfirmed) transfers waiting for a store to confirm
-- 查询等待某门店确认的调拨单（未确认 = 仍在途中）
CREATE INDEX IF NOT EXISTS idx_transfer_pending
  ON public.store_transfer_list (target_store_id)
  WHERE confirmed_at IS NULL;

-- =============================================
-- Trigger: auto-refresh updated_at (reuses set_updated_at() from file 03)
-- 触发器：自动刷新 updated_at（复用 03_user_list 中的 set_updated_at()）
-- =============================================
DROP TRIGGER IF EXISTS trg_store_transfer_list_updated_at ON public.store_transfer_list;
CREATE TRIGGER trg_store_transfer_list_updated_at
BEFORE UPDATE ON public.store_transfer_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
