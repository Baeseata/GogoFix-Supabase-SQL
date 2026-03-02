-- =========================================
-- 17 · store_transfer_list 门店间调拨主表
-- =========================================
-- 依赖: 01_store_list (store_id / target_store_id FK)
--        03_user_list (created_by_user_id / confirmed_by_user_id FK)
-- 被依赖: 18_store_transfer_line_list (store_transfer_id FK)
--
-- 记录门店间的库存调拨单，支持 tracked / untracked / serialized 商品
-- 仅在联网时可操作，不支持离线
-- 设计上只允许 INSERT 和确认收货时的 UPDATE，不应删除（但数据库不做强制拦截，留后余地）

CREATE TABLE IF NOT EXISTS public.store_transfer_list (

  -- 全局自增主键，从 0 开始
  store_transfer_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- 调出门店（发货方）
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 调入门店（收货方）
  target_store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 创建调拨单的用户
  created_by_user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- 确认收货的用户；NULL 表示尚未确认（仍在途中）
  confirmed_by_user_id integer DEFAULT NULL REFERENCES public.user_list(user_id),

  -- 确认收货时间；NULL 表示尚未确认
  -- confirmed_at 和 confirmed_by_user_id 应同时为空或同时有值（见下方 CHECK）
  confirmed_at timestamptz DEFAULT NULL,

  -- 调拨总成本（客户端计算后传入）
  cost_total numeric(10,2) NOT NULL DEFAULT 0,

  -- 调拨总价值（客户端计算后传入）
  price_total numeric(10,2) NOT NULL DEFAULT 0,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- 不能自己调给自己
  CONSTRAINT store_transfer_not_self
    CHECK (store_id != target_store_id),

  -- 确认状态一致性：confirmed_by_user_id 和 confirmed_at 应同时为空或同时有值
  CONSTRAINT store_transfer_confirm_consistency
    CHECK (
      (confirmed_by_user_id IS NULL AND confirmed_at IS NULL)
      OR
      (confirmed_by_user_id IS NOT NULL AND confirmed_at IS NOT NULL)
    )
);

-- =========================================
-- 索引
-- =========================================

-- 查询门店发出的调拨单
CREATE INDEX IF NOT EXISTS idx_transfer_store
  ON public.store_transfer_list (store_id, created_at DESC);

-- 查询门店收到的调拨单
CREATE INDEX IF NOT EXISTS idx_transfer_target_store
  ON public.store_transfer_list (target_store_id, created_at DESC);

-- 查待确认的调拨单（未确认 = 仍在途中）
CREATE INDEX IF NOT EXISTS idx_transfer_pending
  ON public.store_transfer_list (target_store_id)
  WHERE confirmed_at IS NULL;

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_store_transfer_updated_at ON public.store_transfer_list;
CREATE TRIGGER trg_store_transfer_updated_at
BEFORE UPDATE ON public.store_transfer_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
