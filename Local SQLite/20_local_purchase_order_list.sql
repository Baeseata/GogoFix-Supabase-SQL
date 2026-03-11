-- Local SQLite version of 20_purchase_order_list.sql
-- Source: Supabase SQL/20_cloud_purchase_order_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS purchase_order_list (


  -- 门店 ID
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- 采购单编号，同一门店内从 1 开始自动递增，由触发器分配
  purchase_order_id integer NOT NULL,

  -- 供应商
  supplier_id integer DEFAULT NULL REFERENCES supplier_list(supplier_id),

  -- 操作人
  user_id integer NOT NULL REFERENCES user_list(user_id),

  -- 采购单备注 / 描述
  description text DEFAULT NULL,

  -- 采购总成本（客户端计算后传入）
  total_cost numeric NOT NULL DEFAULT 0,

  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- 软删除时间戳
  deleted_at text DEFAULT NULL,

  -- 联合主键：同一门店内采购单编号唯一
  CONSTRAINT purchase_order_list_pk PRIMARY KEY (store_id, purchase_order_id)
);
