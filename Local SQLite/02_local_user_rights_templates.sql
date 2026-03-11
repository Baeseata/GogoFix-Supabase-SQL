-- Local SQLite version of 02_user_rights_templates.sql
-- Source: Supabase SQL/02_cloud_user_rights_templates.sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS user_rights_templates (


  -- Auto-increment primary key, starting from 1; should not be manually assigned
  -- 模板自增主键，从 1 开始；业务端不应手动指定
  template_id integer PRIMARY KEY AUTOINCREMENT,

  -- Template display name, globally unique; used in UI for identification
  -- 模板名称，全局唯一；用于 UI 展示和识别
  template_name text NOT NULL,

  -- Optional description / notes about this template
  -- 模板描述/备注（可选）
  description text DEFAULT NULL,

  -- =============================================
  -- Permission flags (integer, all default to false)
  -- 权限字段（布尔值，默认均为 false）
  -- =============================================

  -- Can view business reports (sales summaries, daily totals, profit reports, etc.)
  -- 是否可以查看经营报表（销售汇总、日结、利润报表等）
  can_view_report integer NOT NULL DEFAULT 0,

  -- Can modify store settings (store info, tax rates, receipt layout, etc.)
  -- 是否可以修改门店设置（门店信息、税率、收据样式等）
  can_edit_settings integer NOT NULL DEFAULT 0,

  -- Can create / edit invoices, quotes, and modification orders
  -- 是否可以编辑/创建发票（含报价单、修改单等）
  can_edit_invoice integer NOT NULL DEFAULT 0,

  -- Can manage other employees (assign permissions, edit employee profiles, etc.)
  -- 是否可以管理其他员工（设置权限、修改员工信息等）
  can_manage_user integer NOT NULL DEFAULT 0,

  -- Can use the stocktake feature to manually adjust inventory quantities
  -- 是否可以使用盘点功能手动调整库存数量
  can_adjust_inventory integer NOT NULL DEFAULT 0,

  -- Whether this is a "full-access info" user:
  --   true  = UI displays all real business data (cost, profit, margins, etc.)
  --   false = UI hides or masks sensitive data, showing substitute content
  -- 是否为"真实信息"用户：
  --   true  = UI 正常显示所有真实业务数据（成本、利润等）
  --   false = UI 层面隐藏或脱敏信息，展示替代内容
  is_true_user integer NOT NULL DEFAULT 1,

  -- UNIQUE: template name must be globally unique
  -- 唯一约束：模板名称必须全局唯一
  CONSTRAINT uq_user_rights_templates_name UNIQUE (template_name)
);
