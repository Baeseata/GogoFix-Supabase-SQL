-- Last updated (America/Toronto): 2026-03-06 13:47:38 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 13:47:38 EST
-- Async requirement: YES - offline POS must continue high-frequency essential operations using local snapshot; sync changes to cloud after reconnection.
-- 异步需求：是 - POS 离线时需依赖本地快照继续高频必要操作，网络恢复后将变更同步到云端。
-- =============================================
-- File 12 · transaction_list — Transaction header table
-- 文件 12 · transaction_list — 交易主表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list   (store_id FK)
--   03_user_list    (user_id FK)
--   07_customer_list (customer_id FK)
--   11_shift_list   (store_id, batch_id, shift_id composite FK)
-- Dependents / 被依赖:
--   13_transaction_line_list  (transaction_id FK)
--   16_serialized_event_list  (transaction_id reference, no FK)
-- Shared components created here / 本文件创建的共享组件:
--   ENUM public.transaction_type — this table only
-- =============================================
-- Note: repair_ticket_id FK will be added by ALTER TABLE in file 22_repair_ticket_list
-- 注意：repair_ticket_id 外键将在 22_repair_ticket_list 中通过 ALTER TABLE 添加
-- =============================================

-- =============================================
-- ENUM: transaction_type — Transaction classification
-- 枚举：transaction_type — 交易类型分类
-- =============================================
-- Type is determined by the client based on transaction content and priority rules.
-- The database does NOT validate the type assignment.
-- Priority (high → low): exchange > serialized > repair > sale / refund / payment
-- ─────────────────────────────────────────────
-- 类型由客户端根据交易内容和优先级规则判定，数据库不做校验。
-- 优先级（高→低）：exchange > serialized > repair > sale / refund / payment
--
--   exchange   = Return + re-purchase in the same transaction (any item swap marks it as exchange)
--              = 退货后又换货（只要涉及了任何换购，都标 exchange）
--   serialized = Contains a serialized item sale (priority just below exchange)
--              = 包含序列号商品卖出（优先级仅次于 exchange）
--   repair     = Repair order (only repair parts/services, determined by UI logic)
--              = 修理单（只有修理配件或修理服务，由 UI 逻辑判定）
--   sale       = Standard sales transaction
--              = 最普通的销售交易
--   refund     = Return / refund only (no new purchase)
--              = 仅退货退款
--   payment    = Customer balance operation (top-up, deposit, withdrawal — should be a standalone transaction)
--              = 客户余额变动（充值、存钱、退钱、定金等，应为单独一笔交易）
DO $$
BEGIN
  CREATE TYPE public.transaction_type AS ENUM (
    'exchange', 'serialized', 'repair', 'sale', 'refund', 'payment'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- Table creation / 建表
-- =============================================
CREATE TABLE IF NOT EXISTS public.transaction_list (

  -- UUID v7 primary key, generated client-side for offline support; no DEFAULT
  -- Printed on receipts as the unique transaction reference
  -- UUID v7 主键，由客户端生成，支持离线；不设 DEFAULT
  -- 小票上会打印本 ID 作为交易唯一凭证
  transaction_id uuid PRIMARY KEY,

  -- Store ID, FK to store_list
  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Customer ID (UUID), FK to customer_list; NULL = walk-in customer
  -- 客户 ID（UUID），外键指向 customer_list；NULL 表示散客
  customer_id uuid DEFAULT NULL REFERENCES public.customer_list(customer_id),

  -- Employee who processed this transaction, FK to user_list
  -- 经手人 ID，外键指向 user_list；每笔交易应有经手人
  user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- Human-readable document number for receipts
  -- Format: {store_code}{device_no}S-{YYMMDD}-{NNN} (e.g. D2S-260303-003)
  -- NULL allowed for legacy rows / offline temp rows before server normalization
  -- 小票可读单号
  -- 格式：{store_code}{device_no}S-{YYMMDD}-{NNN}（例如 D2S-260303-003）
  -- 兼容历史数据与离线临时记录：允许为 NULL
  display_no text DEFAULT NULL,

  -- Legacy per-store sequential integer (kept for backward compatibility)
  -- 历史整型展示编号（为兼容旧逻辑保留）
  store_transaction_id integer DEFAULT NULL,

  -- Batch ID (must be assigned before creating a transaction)
  -- 批次 ID（创建交易前必须先分配）
  batch_id integer NOT NULL,

  -- Shift ID (must be assigned before creating a transaction)
  -- 班次 ID（创建交易前必须先分配）
  shift_id integer NOT NULL,

  -- Related transaction ID: for refund/exchange, points to the original transaction
  -- No FK constraint: the original transaction may not yet be synced (offline scenario)
  -- 关联交易 ID：退货/换货时指向原交易的 transaction_id
  -- 不加外键约束：关联的原交易可能尚未同步到服务端（离线场景）
  related_transaction_id uuid DEFAULT NULL,

  -- Transaction type, determined by client using priority rules (see ENUM above)
  -- 交易类型，由客户端根据优先级规则判定（参见上方枚举）
  type public.transaction_type NOT NULL,

  -- Last edit timestamp; NULL = never edited, non-NULL = time of most recent edit
  -- 编辑时间戳；NULL 表示未编辑过，有值 = 最近一次编辑时间
  edited_at timestamptz DEFAULT NULL,

  -- =============================================
  -- Payment method breakdown (all NOT NULL DEFAULT 0)
  -- 支付方式金额明细（均 NOT NULL DEFAULT 0）
  -- =============================================

  -- Cash payment amount
  -- 现金支付金额
  cash numeric(10,2) NOT NULL DEFAULT 0,

  -- Credit card payment amount
  -- 信用卡支付金额
  credit numeric(10,2) NOT NULL DEFAULT 0,

  -- Debit card payment amount
  -- 借记卡支付金额
  debit numeric(10,2) NOT NULL DEFAULT 0,

  -- Amount paid from customer's store balance
  -- 从客户余额中扣除的金额
  balance numeric(10,2) NOT NULL DEFAULT 0,

  -- =============================================
  -- Summary amounts (all NOT NULL DEFAULT 0)
  -- 汇总金额（均 NOT NULL DEFAULT 0）
  -- =============================================

  -- Transaction total = cash + credit + debit + balance (validated by CHECK below)
  -- 交易总额 = cash + credit + debit + balance（由下方 CHECK 约束校验）
  amount_total numeric(10,2) NOT NULL DEFAULT 0,

  -- Total tax amount
  -- 税额合计
  tax_total numeric(10,2) NOT NULL DEFAULT 0,

  -- Total cost (even for payment-type transactions, cost remains 0, not NULL)
  -- 成本合计（即使是 payment 类型，cost 仍为 0，不为 NULL）
  cost_total numeric(10,2) NOT NULL DEFAULT 0,

  -- Profit = amount_total - tax_total - cost_total (validated by CHECK below)
  -- 利润 = amount_total - tax_total - cost_total（由下方 CHECK 约束校验）
  profit_total numeric(10,2) NOT NULL DEFAULT 0,

  -- =============================================
  -- Notes / 备注
  -- =============================================

  -- Note printed on the customer receipt (customer-visible)
  -- 打印在小票上的备注（客户可见）
  note_on_receipt text DEFAULT NULL,

  -- Internal system note (staff-only, not printed)
  -- 系统内部备注（仅员工可见，不打印）
  note_on_system text DEFAULT NULL,

  -- =============================================
  -- Device / 设备
  -- =============================================

  -- Device ID: generated by the client on first launch and permanently saved
  -- 设备 ID：客户端首次启动时生成并永久保存
  device_id text DEFAULT NULL,

  -- repair_ticket_id will be added by ALTER TABLE in file 22_repair_ticket_list
  -- repair_ticket_id 将在 22_repair_ticket_list 中通过 ALTER TABLE 添加

  -- =============================================
  -- Timestamps / 时间戳
  -- =============================================

  -- Client-side creation timestamp (provided by client for offline scenarios)
  -- 客户端本地创建时间（离线场景下由客户端提供）
  created_at timestamptz NOT NULL,

  -- First sync timestamp to Supabase; NULL = not yet synced
  -- 首次同步到 Supabase 的时间；NULL 表示尚未同步
  synced_at timestamptz DEFAULT NULL,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL,

  -- Soft delete timestamp; NULL = active, non-NULL = voided
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已作废
  deleted_at timestamptz DEFAULT NULL,

  -- =============================================
  -- CHECK constraints: validate client-side calculations to prevent dirty data
  -- 兜底校验：确保客户端计算正确，阻止脏数据入库
  -- =============================================

  -- CHECK: amount_total must equal the sum of all payment methods
  -- 约束：交易总额必须等于所有支付方式之和
  CONSTRAINT chk_transaction_list_amount_total
    CHECK (amount_total = cash + credit + debit + balance),

  -- CHECK: profit_total must equal amount_total minus tax and cost
  -- 约束：利润必须等于总额减去税和成本
  CONSTRAINT chk_transaction_list_profit_total
    CHECK (profit_total = amount_total - tax_total - cost_total),

  -- Optional format guard for display_no
  -- 显示单号格式校验（可空）
  CONSTRAINT chk_transaction_list_display_no_format
    CHECK (
      display_no IS NULL
      OR display_no ~ '^[A-Za-z0-9]+S-[0-9]{6}-[0-9]{3}$'
    )
);

-- =============================================
-- Composite FK to shift_list (store_id, batch_id, shift_id)
-- batch_id and shift_id are required to be non-NULL
-- ─────────────────────────────────────────────
-- 复合外键指向 shift_list (store_id, batch_id, shift_id)
-- batch_id 和 shift_id 为必填（不可为 NULL）
-- =============================================
DO $$
BEGIN
  ALTER TABLE public.transaction_list
    ADD CONSTRAINT fk_transaction_list_shift_list
    FOREIGN KEY (store_id, batch_id, shift_id)
    REFERENCES public.shift_list (store_id, batch_id, shift_id);
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- Migration safety patch: enforce non-null shift linkage for existing databases
-- 迁移兼容补丁：对已存在数据库强制 batch_id / shift_id 非空
-- =============================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.transaction_list
    WHERE batch_id IS NULL OR shift_id IS NULL
  ) THEN
    ALTER TABLE public.transaction_list
      ALTER COLUMN batch_id SET NOT NULL,
      ALTER COLUMN shift_id SET NOT NULL;
  ELSE
    RAISE NOTICE 'Skip SET NOT NULL on transaction_list.batch_id/shift_id because NULL rows exist.';
  END IF;
END $$;

-- =============================================
-- Migration safety patch: add display_no for existing databases
-- 迁移兼容补丁：为已存在数据库补充 display_no 列
-- =============================================
ALTER TABLE public.transaction_list
  ADD COLUMN IF NOT EXISTS display_no text;

DO $$
BEGIN
  ALTER TABLE public.transaction_list
    ADD CONSTRAINT chk_transaction_list_display_no_format
    CHECK (
      display_no IS NULL
      OR display_no ~ '^[A-Za-z0-9]+S-[0-9]{6}-[0-9]{3}$'
    );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- =============================================
-- Partial unique index: display_no must be unique within a store (active rows)
-- 部分唯一索引：display_no 在门店内唯一（仅活跃且非空记录）
-- =============================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_transaction_store_display_no
  ON public.transaction_list (store_id, display_no)
  WHERE display_no IS NOT NULL AND deleted_at IS NULL;

-- =============================================
-- Partial unique index: store_transaction_id must be unique within a store (only when assigned)
-- 部分唯一索引：store_transaction_id 在门店内唯一（仅在已分配时生效）
-- =============================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_store_transaction_id
  ON public.transaction_list (store_id, store_transaction_id)
  WHERE store_transaction_id IS NOT NULL;

-- =============================================
-- Trigger: auto-refresh updated_at (reuses set_updated_at() from file 03)
-- 触发器：自动刷新 updated_at（复用 03_user_list 中的 set_updated_at()）
-- =============================================
DROP TRIGGER IF EXISTS trg_transaction_list_updated_at ON public.transaction_list;
CREATE TRIGGER trg_transaction_list_updated_at
BEFORE UPDATE ON public.transaction_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =============================================
-- Indexes / 索引
-- =============================================

-- Most common query: list transactions for a store (active only, newest first)
-- 最常见查询：列出门店的交易（仅活跃记录，按时间倒序）
CREATE INDEX IF NOT EXISTS idx_transaction_store
  ON public.transaction_list (store_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- Look up transaction history for a specific customer
-- 查询某客户的交易历史
CREATE INDEX IF NOT EXISTS idx_transaction_customer
  ON public.transaction_list (customer_id)
  WHERE deleted_at IS NULL AND customer_id IS NOT NULL;

-- Filter transactions by type within a store
-- 按交易类型筛选（门店内）
CREATE INDEX IF NOT EXISTS idx_transaction_type
  ON public.transaction_list (store_id, type)
  WHERE deleted_at IS NULL;

-- Look up transactions by employee
-- 按经手人查交易
CREATE INDEX IF NOT EXISTS idx_transaction_user
  ON public.transaction_list (user_id)
  WHERE deleted_at IS NULL;

-- Look up related transactions (for refund/exchange tracing)
-- 查询关联交易（退货/换货溯源）
CREATE INDEX IF NOT EXISTS idx_transaction_related
  ON public.transaction_list (related_transaction_id)
  WHERE related_transaction_id IS NOT NULL;
