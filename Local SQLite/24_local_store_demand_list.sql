-- Local SQLite version of 24_store_demand_list.sql
-- Source: Supabase SQL/24_cloud_store_demand_list.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS store_demand_list (


  -- Store ID, FK to store_list
  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Per-store demand number, auto-assigned by trigger (starts at 0)
  -- 门店内需求编号，由触发器自动分配（从 1 开始）
  demand_id integer NOT NULL,

  -- Demand tag/category (client-managed vocabulary)
  -- 需求标签/分类（由客户端管理标签字典）
  tag text NOT NULL,

  -- Review workflow status
  -- 审核流程状态
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','rejected','done')),

  -- Demand content in plain text; can contain multiple items
  -- 需求正文（纯文本）；可在一行中写多个需求项
  content text NOT NULL,

  -- Creator user
  -- 创建人
  created_by integer NOT NULL REFERENCES user_list(user_id),

  -- Creation time
  -- 创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Reviewer user (manager+), NULL before review
  -- 审核人（manager+），未审核前为 NULL
  reviewed_by integer DEFAULT NULL REFERENCES user_list(user_id),

  -- Review timestamp, NULL before review
  -- 审核时间，未审核前为 NULL
  reviewed_at text DEFAULT NULL,

  -- Review note / rejection reason / handling instruction
  -- 审核备注 / 驳回原因 / 处理说明
  manager_note text DEFAULT NULL,

  -- Last update timestamp (auto-refreshed by trigger)
  -- 最后更新时间（由触发器自动刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Soft delete timestamp
  -- 软删除时间戳
  deleted_at text DEFAULT NULL,

  -- Composite PK ensures demand_id uniqueness within each store
  -- 联合主键保证 demand_id 在门店内唯一
  CONSTRAINT store_demand_list_pkey PRIMARY KEY (store_id, demand_id),

  -- demand_id must be non-negative
  -- demand_id 必须为非负整数
  CONSTRAINT chk_store_demand_id_non_negative CHECK (demand_id >= 0),

  -- Review fields should be set together (both NULL or both non-NULL)
  -- 审核字段应同时为空或同时有值
  CONSTRAINT chk_store_demand_review_pair CHECK (
    (reviewed_by IS NULL AND reviewed_at IS NULL)
    OR
    (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
  )
);
