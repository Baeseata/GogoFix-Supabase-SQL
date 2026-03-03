-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 14 · store_inventory_adjustment_list — Inventory adjustment header table
-- 文件 14 · store_inventory_adjustment_list — 库存盘点/调整主表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list (store_id FK)
--   03_user_list  (user_id FK)
-- Dependents / 被依赖:
--   15_store_inventory_adjustment_line_list (adjustment_id FK)
-- =============================================
-- Records the header info for each inventory adjustment operation:
-- who did it, which store, when, and the total cost impact.
-- Online-only (no synced_at field — adjustments cannot be performed offline).
-- By design, only INSERT is intended (no UPDATE or DELETE), but the DB does not
-- enforce immutability here to allow future flexibility.
-- ─────────────────────────────────────────────
-- 记录每次库存盘点/调整操作的基本信息：操作人、门店、时间、总成本变动。
-- 仅在联网时可操作，不支持离线（无 synced_at 字段）。
-- 设计上只允许 INSERT，不应 UPDATE 或 DELETE
-- （但数据库层面不做强制拦截，留后余地）。
-- =============================================

CREATE TABLE IF NOT EXISTS public.store_inventory_adjustment_list (

  -- Auto-increment primary key, starting from 0
  -- 全局自增主键，从 0 开始
  adjustment_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- Store where this adjustment was performed, FK to store_list
  -- 执行盘点的门店，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Employee who performed this adjustment, FK to user_list
  -- 执行盘点的员工，外键指向 user_list
  user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- Total cost impact of this adjustment (sum of all line item cost deltas)
  -- Calculated by the client and passed in; the DB does NOT auto-aggregate
  -- 本次盘点造成的总成本变动（所有明细行的成本差额汇总）
  -- 由客户端计算后传入，数据库不做自动汇总
  cost_delta numeric(10,2) NOT NULL DEFAULT 0,

  -- Reason / description for this adjustment (e.g., "Monthly stocktake", "Damage write-off")
  -- 盘点备注/原因说明（如"月度盘点"、"损坏报废"）
  description text DEFAULT NULL,

  -- Creation timestamp (server time, since this is an online-only operation)
  -- 创建时间（服务端时间，因为此操作仅在联网时进行）
  created_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================
-- Indexes / 索引
-- =============================================

-- Look up adjustment history for a store (newest first)
-- 查询门店的盘点记录（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_adjustment_list_store
  ON public.store_inventory_adjustment_list (store_id, created_at DESC);

-- Look up which adjustments a specific employee performed
-- 查询某员工执行的盘点操作
CREATE INDEX IF NOT EXISTS idx_adjustment_list_user
  ON public.store_inventory_adjustment_list (user_id);
