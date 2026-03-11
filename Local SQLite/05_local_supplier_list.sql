-- Local SQLite version of 05_supplier_list.sql
-- Source: Supabase SQL/05_cloud_supplier_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS supplier_list (


  -- Auto-increment primary key, starting from 1; should not be manually assigned
  -- 全局自增主键，从 1 开始；业务端不应手动指定
  supplier_id integer PRIMARY KEY AUTOINCREMENT,

  -- Supplier name; unique among active (non-deleted) records via partial unique index below
  -- 供应商名称；在活跃（未删除）记录中唯一（见下方 partial unique index）
  supplier_name text NOT NULL,

  -- Supplier phone number (optional)
  -- 供应商电话（可选）
  supplier_phone_number text DEFAULT NULL,

  -- Supplier email address (optional)
  -- 供应商邮箱（可选）
  supplier_email_address text DEFAULT NULL,

  -- Store that created this supplier record
  -- 创建该供应商记录的门店 ID
  created_store_id text NOT NULL REFERENCES store_list(store_id),

  -- Record creation timestamp
  -- 记录创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Soft delete timestamp; NULL = active, non-NULL = disabled
  -- 软删除时间戳；NULL 表示正常，非 NULL 表示已停用
  deleted_at text DEFAULT NULL
);
