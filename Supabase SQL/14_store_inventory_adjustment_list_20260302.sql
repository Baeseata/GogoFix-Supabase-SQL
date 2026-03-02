-- =========================================
-- 14 · store_inventory_adjustment_list 盘点主表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        03_user_list (user_id FK)
-- 被依赖: 15_store_inventory_adjustment_line_list (adjustment_id FK)
--
-- 记录每次盘点操作的基本信息：谁、哪个门店、何时发、总成本变动
-- 仅在联网时可操作，不支持离线
-- 设计上只允许 INSERT，不应 UPDATE 或 DELETE（但数据库层面不做强制拦截，留后余地）

CREATE TABLE IF NOT EXISTS public.store_inventory_adjustment_list (

  -- 全局自增主键，从 0 开始
  adjustment_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- 门店 ID
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 操作人
  user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- 本次盘点造成的总成本变动（所有明细行的成本差额汇总）
  -- 由客户端计算后传入，数据库不做自动汇总
  cost_delta numeric(10,2) NOT NULL DEFAULT 0,

  -- 盘点备注 / 原因说明
  description text DEFAULT NULL,

  -- 创建时间（联网操作，使用服务端时间）
  created_at timestamptz NOT NULL DEFAULT now()
);

-- =========================================
-- 索引
-- =========================================

-- 查询门店的盘点记录（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_adjustment_store
  ON public.store_inventory_adjustment_list (store_id, created_at DESC);

-- 查询用户的盘点操作
CREATE INDEX IF NOT EXISTS idx_adjustment_user
  ON public.store_inventory_adjustment_list (user_id);
