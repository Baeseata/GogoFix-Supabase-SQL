-- Async requirement: YES - offline POS must continue high-frequency essential operations using local snapshot; sync changes to cloud after reconnection.
-- 异步需求：是 - POS 离线时需依赖本地快照继续高频必要操作，网络恢复后将变更同步到云端。
-- =============================================
-- File 07 · customer_list — Customer master table
-- 文件 07 · customer_list — 客户主表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list (created_store_id FK)
-- Dependents / 被依赖:
--   12_transaction_list   (customer_id FK)
--   22_repair_ticket_list (customer_id FK)
-- =============================================
-- Supports offline creation: PK is a UUID v7 generated client-side.
-- When offline, the client generates the UUID locally; it syncs to Supabase when online.
-- ─────────────────────────────────────────────
-- 支持离线创建：主键由客户端生成 UUID v7。
-- 离线时客户端自行生成，联网后同步写入 Supabase。
-- =============================================

CREATE TABLE IF NOT EXISTS public.customer_list (

  -- UUID v7 primary key, generated client-side for offline support
  -- Printed on receipts as a unique customer reference
  -- UUID v7 主键，客户端生成，支持离线创建
  -- 小票上会打印本 ID 作为客户唯一凭证
  customer_id uuid PRIMARY KEY,

  -- Customer name; may be NULL for anonymous customers or to be filled in later
  -- 客户姓名；匿名客户或稍后补填时可为空
  customer_name text DEFAULT NULL,

  -- Optional description / notes about this customer
  -- 客户备注描述（可选）
  description text DEFAULT NULL,

  -- Phone number stored as text; NULL = unknown
  -- Unique among active customers via partial unique index (see below)
  -- After soft delete, the phone number is released for reuse by a new customer
  -- Offline conflict scenario: two stores create a customer with the same phone number offline;
  -- on sync, the second record hits the unique constraint — app layer handles conflict (merge or discard)
  -- 手机号码，以文本存储；NULL 表示未知
  -- 在活跃客户中唯一（见下方 partial unique index）
  -- 软删除后号码释放，可被新客户使用
  -- 离线冲突场景：两个门店离线用同一手机号建客户，同步时第二条会被唯一约束拦截，
  -- 应用层需处理冲突逻辑（提示合并或放弃）
  phone_number text DEFAULT NULL,

  -- Cached field: total balance across all stores for this customer
  -- Updated by business logic / RPC, NOT auto-calculated by the database
  -- 缓存字段：该客户在所有门店的余额合计
  -- 由业务逻辑/RPC 更新，数据库层面不自动计算
  balance_total numeric(10,2) NOT NULL DEFAULT 0,

  -- Client-side creation timestamp (provided by the client for offline scenarios, not server time)
  -- 客户端本地创建时间（离线场景下由客户端提供，不使用服务端时间）
  created_at timestamptz NOT NULL,

  -- First sync timestamp to Supabase; NULL = not yet synced
  -- 首次同步到 Supabase 的时间；NULL 表示尚未同步
  synced_at timestamptz DEFAULT NULL,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL,

  -- Timestamp of last business activity (transaction, modification, payment, etc.)
  -- Updated by business logic / RPC
  -- 最近一次业务活动时间（交易/修改/付款等）
  -- 由业务逻辑/RPC 更新
  last_activity_at timestamptz DEFAULT NULL,

  -- Store that created this customer record
  -- 创建该客户记录的门店 ID
  created_store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Soft delete timestamp; NULL = active, non-NULL = deleted
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已删除
  deleted_at timestamptz DEFAULT NULL
);

-- =============================================
-- Trigger: auto-refresh updated_at on every UPDATE
-- (reuses set_updated_at() created in 03_user_list)
-- 触发器：每次 UPDATE 自动刷新 updated_at
-- （复用 03_user_list 中创建的 set_updated_at()）
-- =============================================
DROP TRIGGER IF EXISTS trg_customer_list_updated_at ON public.customer_list;
CREATE TRIGGER trg_customer_list_updated_at
BEFORE UPDATE ON public.customer_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =============================================
-- Partial unique index: phone number must be unique among active customers with a non-NULL phone
-- Records with phone_number IS NULL are excluded (allows multiple anonymous customers)
-- After soft delete the phone number is released for reuse
-- ─────────────────────────────────────────────
-- 部分唯一索引：活跃且手机号非空的客户中，手机号唯一
-- phone_number IS NULL 的记录不参与唯一性检查（允许多个匿名客户）
-- 软删除后手机号释放，新客户可复用同一号码
-- =============================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_customer_list_phone_active
  ON public.customer_list (phone_number)
  WHERE deleted_at IS NULL AND phone_number IS NOT NULL;

-- =============================================
-- Index: quickly find active customers by store
-- 索引：按门店快速查找活跃客户
-- =============================================
CREATE INDEX IF NOT EXISTS idx_customer_list_active
  ON public.customer_list (created_store_id)
  WHERE deleted_at IS NULL;
