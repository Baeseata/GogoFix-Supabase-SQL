-- =========================================
-- 07 · customer_list 客户主表
-- =========================================
-- 依赖: 01_store_list (created_store_id FK)
-- 被依赖: 12_transaction_list (customer_id FK)
--         22_repair_ticket_list (customer_id FK)
--
-- 支持离线创建：主键由客户端生成 UUID v7，INSERT 时传入
-- 离线时客户端自行生成，联网后同步写入

CREATE TABLE IF NOT EXISTS public.customer_list (

  -- 客户全局唯一主键，由客户端生成 UUID v7，INSERT 时传入
  -- 离线时客户端自行生成，联网后同步写入；小票上会打印本 ID 作为唯一凭证
  customer_id uuid PRIMARY KEY,

  -- 客户姓名，允许为空（匿名客户 / 稍后补填）
  customer_name text DEFAULT NULL,

  -- 客户备注描述
  description text DEFAULT NULL,

  -- 手机号码，以文本存储；NULL 表示未知
  -- 活跃客户中手机号唯一（见下方 partial unique index），软删除后释放号码可被新客户使用
  -- 离线冲突场景：两个门店离线用同一手机号建客户，同步时第二条会唯一约束拦截，
  -- 应用层需处理冲突逻辑（提示合并或放弃）
  phone_number text DEFAULT NULL,

  -- 缓存字段：该客户在所有门店的余额合计
  -- 由业务逻辑 / RPC 更新，数据库层面不自动计算
  balance_total numeric(10,2) NOT NULL DEFAULT 0,

  -- 客户端本地创建时间（离线场景下由客户端提供，不使用服务端时间）
  created_at timestamptz NOT NULL,

  -- 首次同步到云端的时间；NULL 表示尚未同步
  synced_at timestamptz DEFAULT NULL,

  -- 最后修改时间
  updated_at timestamptz NOT NULL,

  -- 最近一次业务活动时间（交易 / 修改 / 付款等），由业务逻辑 / RPC 更新
  last_activity_at timestamptz DEFAULT NULL,

  -- 创建该客户记录的门店 ID
  created_store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已删除
  deleted_at timestamptz DEFAULT NULL
);

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_customer_list_updated_at ON public.customer_list;
CREATE TRIGGER trg_customer_list_updated_at
BEFORE UPDATE ON public.customer_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =========================================
-- 手机号唯一约束（仅活跃客户 + 手机号非空时生效）
-- =========================================
-- 软删除后手机号释放，新客户可复用同一号码
-- phone_number IS NULL 的记录不参与唯一性查询（允许多个匿名客户）
CREATE UNIQUE INDEX IF NOT EXISTS uq_customer_phone_active
  ON public.customer_list (phone_number)
  WHERE deleted_at IS NULL AND phone_number IS NOT NULL;

-- =========================================
-- 活跃客户索引
-- =========================================
CREATE INDEX IF NOT EXISTS idx_customer_active
  ON public.customer_list (created_store_id)
  WHERE deleted_at IS NULL;
