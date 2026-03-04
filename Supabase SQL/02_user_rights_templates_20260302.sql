-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 02 · user_rights_templates — Permission template table
-- 文件 02 · user_rights_templates — 用户权限模板表
-- =============================================
-- Dependencies / 依赖:
--   (none)
--   （无）
-- Dependents / 被依赖:
--   04_store_user_rights (template_id FK)
-- =============================================
-- Defines reusable permission templates for store employees.
-- Each template is a combination of boolean permission flags.
-- Templates are assigned to users per-store via the store_user_rights junction table.
-- Templates do NOT use soft delete: before removing a template, all users
-- referencing it must be migrated to another template first.
-- The FK constraint will block deletion if any user still references the template.
-- ─────────────────────────────────────────────
-- 定义门店员工的权限组合模板。
-- 每个模板是一组布尔权限标志的组合。
-- 通过 store_user_rights 关联表将模板分配给具体门店的具体用户。
-- 模板不使用软删除：停用模板前需先将所有引用该模板的用户迁移至其他模板，
-- 外键约束会阻止在仍有用户引用时直接删除模板，这是预期行为。
-- =============================================

CREATE TABLE IF NOT EXISTS public.user_rights_templates (

  -- Auto-increment primary key, starting from 0; should not be manually assigned
  -- 模板自增主键，从 0 开始；业务端不应手动指定
  template_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- Template display name, globally unique; used in UI for identification
  -- 模板名称，全局唯一；用于 UI 展示和识别
  template_name text NOT NULL,

  -- Optional description / notes about this template
  -- 模板描述/备注（可选）
  description text DEFAULT NULL,

  -- =============================================
  -- Permission flags (boolean, all default to false)
  -- 权限字段（布尔值，默认均为 false）
  -- =============================================

  -- Can view business reports (sales summaries, daily totals, profit reports, etc.)
  -- 是否可以查看经营报表（销售汇总、日结、利润报表等）
  can_view_report boolean NOT NULL DEFAULT false,

  -- Can modify store settings (store info, tax rates, receipt layout, etc.)
  -- 是否可以修改门店设置（门店信息、税率、收据样式等）
  can_edit_settings boolean NOT NULL DEFAULT false,

  -- Can create / edit invoices, quotes, and modification orders
  -- 是否可以编辑/创建发票（含报价单、修改单等）
  can_edit_invoice boolean NOT NULL DEFAULT false,

  -- Can manage other employees (assign permissions, edit employee profiles, etc.)
  -- 是否可以管理其他员工（设置权限、修改员工信息等）
  can_manage_user boolean NOT NULL DEFAULT false,

  -- Can use the stocktake feature to manually adjust inventory quantities
  -- 是否可以使用盘点功能手动调整库存数量
  can_adjust_inventory boolean NOT NULL DEFAULT false,

  -- Whether this is a "full-access info" user:
  --   true  = UI displays all real business data (cost, profit, margins, etc.)
  --   false = UI hides or masks sensitive data, showing substitute content
  -- 是否为"真实信息"用户：
  --   true  = UI 正常显示所有真实业务数据（成本、利润等）
  --   false = UI 层面隐藏或脱敏信息，展示替代内容
  is_true_user boolean NOT NULL DEFAULT true,

  -- UNIQUE: template name must be globally unique
  -- 唯一约束：模板名称必须全局唯一
  CONSTRAINT uq_user_rights_templates_name UNIQUE (template_name)
);
