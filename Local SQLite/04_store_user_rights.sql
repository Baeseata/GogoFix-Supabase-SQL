-- Local SQLite version of 04_store_user_rights.sql
-- Source: Supabase SQL/04_store_user_rights.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS store_user_rights (


  -- User ID, FK to user_list
  -- 用户 ID，外键指向 user_list
  user_id integer NOT NULL REFERENCES user_list(user_id),

  -- Store ID, FK to store_list
  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES store_list(store_id),

  -- Permission template ID, FK to user_rights_templates
  -- 权限模板 ID，外键指向 user_rights_templates
  template_id integer NOT NULL REFERENCES user_rights_templates(template_id),

  -- Record creation timestamp
  -- 记录创建时间
  created_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at text NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Composite PK: one user can have only one permission template per store
  -- 联合主键：同一用户在同一门店只能有一个权限模板
  CONSTRAINT store_user_rights_pkey PRIMARY KEY (user_id, store_id)
);
