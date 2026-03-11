-- Local SQLite version of 07_customer_list.sql
-- Source: Supabase SQL/07_cloud_customer_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS customer_list (


  -- UUID v7 primary key, generated client-side for offline support
  -- Printed on receipts as a unique customer reference
  -- UUID v7 主键，客户端生成，支持离线创建
  -- 小票上会打印本 ID 作为客户唯一凭证
  customer_id text PRIMARY KEY,

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
  balance_total numeric NOT NULL DEFAULT 0,

  -- Client-side creation timestamp (provided by the client for offline scenarios, not server time)
  -- 客户端本地创建时间（离线场景下由客户端提供，不使用服务端时间）
  created_at text NOT NULL,

  -- First sync timestamp to Supabase; NULL = not yet synced
  -- 首次同步到 Supabase 的时间；NULL 表示尚未同步
  synced_at text DEFAULT NULL,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at text NOT NULL,

  -- Timestamp of last business activity (transaction, modification, payment, etc.)
  -- Updated by business logic / RPC
  -- 最近一次业务活动时间（交易/修改/付款等）
  -- 由业务逻辑/RPC 更新
  last_activity_at text DEFAULT NULL,

  -- Store that created this customer record
  -- 创建该客户记录的门店 ID
  created_store_id text NOT NULL REFERENCES store_list(store_id),

  -- Soft delete timestamp; NULL = active, non-NULL = deleted
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已删除
  deleted_at text DEFAULT NULL
);
