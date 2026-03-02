-- =========================================
-- 12 · transaction_list 交易主表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        03_user_list (user_id FK)
--        07_customer_list (customer_id FK)
--        11_shift_list (store_id, batch_id, shift_id 复合 FK)
-- 被依赖: 13_transaction_line_list (transaction_id FK)
--         16_serialized_event_list (transaction_id 引用，无 FK)
--
-- 注意: repair_ticket_id FK 在 22_repair_ticket_list 中通过 ALTER TABLE 添加

-- =========================================
-- ENUM: transaction_type 交易类型枚举
-- =========================================
-- 类型判定由客户端根据交易内容和优先级规则决定，数据库不做校验
-- 优先级（高→低）：exchange > serialized > repair > sale / refund / payment
--   exchange   = 退货后又换货（只要涉及了任何 item，不管多少，都标 exchange）
--   serialized = 包含 serialized item 卖出（优先级仅次于 exchange）
--   repair     = 修理单（只有 repair parts 或 repair service 都标 repair，UI 方面实现）
--   sale       = 最普通的销售交易
--   refund     = 仅退货退款
--   payment    = 客户对 balance 进行变动（充值、存钱、退钱、定金等，应为单独一个 transaction）
DO $$
BEGIN
  CREATE TYPE public.transaction_type AS ENUM (
    'exchange', 'serialized', 'repair', 'sale', 'refund', 'payment'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =========================================
-- 建表
-- =========================================
CREATE TABLE IF NOT EXISTS public.transaction_list (

  -- 全局唯一主键，由客户端生成 UUID v7，INSERT 时传入，不设 DEFAULT
  -- 离线时客户端自行生成，联网后同步写入；小票上会打印本 ID 作为唯一凭证
  transaction_id uuid PRIMARY KEY,

  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 客户 ID（uuid），外键指向 customer_list；NULL 表示 walk-in 散客
  customer_id uuid DEFAULT NULL REFERENCES public.customer_list(customer_id),

  -- 经手人 ID，外键指向 user_list；每笔交易应有经手人
  user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- 门店内顺序展示 ID，从 1 开始，联网同步时由数据库分配
  -- 离线时客户端生成临时 ID 用于本地展示，实际 supabase 不储存临时 ID
  -- 联网同步时才统一分配正式编号，因此 INSERT 时可能为 NULL
  store_transaction_id integer DEFAULT NULL,

  -- 批次 ID（联网同步时填入，离线时可能为 NULL）
  batch_id integer DEFAULT NULL,

  -- 班次 ID（后续会建 shift 外键，联网同步时填入，离线时可能为 NULL）
  shift_id integer DEFAULT NULL,

  -- 关联交易 ID：refund / exchange 时指向原交易的 transaction_id
  -- 不加外键约束：因为关联的原交易可能尚未同步到服务端（离线场景）
  related_transaction_id uuid DEFAULT NULL,

  -- 交易类型，由客户端根据优先级规则判定
  type public.transaction_type NOT NULL,

  -- 编辑时间戳：NULL 表示未编辑过，有值 = 最近一次编辑时间
  edited_at timestamptz DEFAULT NULL,

  -- =========================================
  -- 支付方式金额明细（均 NOT NULL DEFAULT 0）
  -- =========================================

  -- 现金
  cash numeric(10,2) NOT NULL DEFAULT 0,

  -- 信用卡
  credit numeric(10,2) NOT NULL DEFAULT 0,

  -- 借记卡
  debit numeric(10,2) NOT NULL DEFAULT 0,

  -- 客户从自身 balance 释放的钱
  balance numeric(10,2) NOT NULL DEFAULT 0,

  -- =========================================
  -- 汇总金额（均 NOT NULL DEFAULT 0）
  -- =========================================

  -- 交易总额 = cash + credit + debit + balance
  amount_total numeric(10,2) NOT NULL DEFAULT 0,

  -- 税额合计
  tax_total numeric(10,2) NOT NULL DEFAULT 0,

  -- 成本合计（即使是 payment 类型，cost 仍为 0，不为 NULL）
  cost_total numeric(10,2) NOT NULL DEFAULT 0,

  -- 利润 = amount_total - tax_total - cost_total
  profit_total numeric(10,2) NOT NULL DEFAULT 0,

  -- =========================================
  -- 备注
  -- =========================================

  -- 打印在小票上的备注（客户可见）
  note_on_receipt text DEFAULT NULL,

  -- 系统内部备注（仅员工可见，不打印）
  note_on_system text DEFAULT NULL,

  -- =========================================
  -- 设备与班次
  -- =========================================

  -- 设备 ID，客户端首次启动时生成并永久保存（后续会建 device 表，暂时可补外键）
  device_id text DEFAULT NULL,

  -- repair_ticket_id 将在 22_repair_ticket_list 中通过 ALTER TABLE 添加

  -- =========================================
  -- 时间戳
  -- =========================================

  -- 客户端本地创建时间（离线场景下由客户端提供）
  created_at timestamptz NOT NULL,

  -- 首次同步到云端的时间；NULL 表示尚未同步
  synced_at timestamptz DEFAULT NULL,

  -- 最后修改时间
  updated_at timestamptz NOT NULL,

  -- 软删除时间戳
  deleted_at timestamptz DEFAULT NULL,

  -- =========================================
  -- 兜底校验：确保客户端计算正确，阻止脏数据入库
  -- =========================================
  CONSTRAINT transaction_amount_total_check
    CHECK (amount_total = cash + credit + debit + balance),

  CONSTRAINT transaction_profit_total_check
    CHECK (profit_total = amount_total - tax_total - cost_total)
);

-- =========================================
-- shift 外键（store_id, batch_id, shift_id → shift_list）
-- =========================================
-- 因为支持离线创建，batch_id 和 shift_id 可能在离线时为 NULL
DO $$
BEGIN
  ALTER TABLE public.transaction_list
    ADD CONSTRAINT fk_transaction_shift
    FOREIGN KEY (store_id, batch_id, shift_id)
    REFERENCES public.shift_list (store_id, batch_id, shift_id);
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =========================================
-- store_transaction_id 门店内唯一（联网分配后生效）
-- =========================================
-- 仅在 store_transaction_id 已分配（非 NULL）时参与唯一性查询
CREATE UNIQUE INDEX IF NOT EXISTS uq_store_transaction_id
  ON public.transaction_list (store_id, store_transaction_id)
  WHERE store_transaction_id IS NOT NULL;

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_transaction_list_updated_at ON public.transaction_list;
CREATE TRIGGER trg_transaction_list_updated_at
BEFORE UPDATE ON public.transaction_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =========================================
-- 索引
-- =========================================

-- 按门店查交易（最常见的查询场景）
CREATE INDEX IF NOT EXISTS idx_transaction_store
  ON public.transaction_list (store_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- 按客户查交易历史
CREATE INDEX IF NOT EXISTS idx_transaction_customer
  ON public.transaction_list (customer_id)
  WHERE deleted_at IS NULL AND customer_id IS NOT NULL;

-- 按交易类型过滤
CREATE INDEX IF NOT EXISTS idx_transaction_type
  ON public.transaction_list (store_id, type)
  WHERE deleted_at IS NULL;

-- 按经手人查交易
CREATE INDEX IF NOT EXISTS idx_transaction_user
  ON public.transaction_list (user_id)
  WHERE deleted_at IS NULL;

-- 查关联交易（refund / exchange 溯源）
CREATE INDEX IF NOT EXISTS idx_transaction_related
  ON public.transaction_list (related_transaction_id)
  WHERE related_transaction_id IS NOT NULL;
