-- =========================================
-- 02 · user_rights_templates 用户权限模板表
-- =========================================
-- 依赖: 无
-- 被依赖: 04_store_user_rights (template_id FK)
--
-- 定义门店员工的权限组合模板，通过关联表分配给具体门店的具体用户
-- 模板不使用软删除：停用模板前需先将所有引用该模板的用户迁移至其他模板，
-- 外键约束会阻止在仍有用户引用时直接删除模板，这是预期行为

CREATE TABLE IF NOT EXISTS public.user_rights_templates (

  -- 模板自增主键，从 0 开始，业务端不应手动指定
  template_id integer
    GENERATED ALWAYS AS IDENTITY (START WITH 0 MINVALUE 0)
    PRIMARY KEY,

  -- 模板名称，全局唯一，用于 UI 展示和识别
  template_name text NOT NULL,

  -- 模板描述 / 备注
  description text DEFAULT NULL,

  -- =========================================
  -- 权限字段（boolean，默认均为 false）
  -- =========================================

  -- 是否可以查看经营报表
  can_view_report boolean NOT NULL DEFAULT false,

  -- 是否可以修改门店设置
  can_edit_settings boolean NOT NULL DEFAULT false,

  -- 是否可以编辑 / 创建发票（含报价单、修改单等）
  can_edit_invoice boolean NOT NULL DEFAULT false,

  -- 是否可以管理其他员工（设置权限、修改员工信息等）
  can_manage_user boolean NOT NULL DEFAULT false,

  -- 是否可以使用盘点功能手动调整库存数量
  can_adjust_inventory boolean NOT NULL DEFAULT false,

  -- 是否为"真实信息"用户：
  --   true  = UI 正常显示所有真实业务数据（成本、利润等）
  --   false = UI 层面隐藏或脱敏信息，展示替代内容
  is_true_user boolean NOT NULL DEFAULT true,

  -- 模板名称唯一约束
  CONSTRAINT uq_user_rights_templates_name UNIQUE (template_name)
);
