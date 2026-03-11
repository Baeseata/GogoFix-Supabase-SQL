-- Last updated (America/Toronto): 2026-03-06 13:47:38 EST
-- 最后更新时间（蒙特利尔时区）: 2026-03-06 13:47:38 EST
-- Async requirement: NO - cloud-first table; offline local snapshot support is not required for high-frequency essential POS operations.
-- 异步需求：否 - 该表采用云端优先，不要求离线本地快照支持高频必要 POS 操作。
-- =============================================
-- File 04 · store_user_rights — Store-User-Permission junction table
-- 文件 04 · store_user_rights — 门店-用户-权限关联表
-- =============================================
-- Dependencies / 依赖:
--   01_store_list  (store_id FK)
--   02_user_rights_templates (template_id FK)
--   03_user_list   (user_id FK)
-- Dependents / 被依赖:
--   (none)
--   （无）
-- =============================================
-- Junction table that links a user to a permission template within a specific store.
-- PK = (user_id, store_id), meaning each user can have exactly ONE permission
-- template per store (but may have different templates in different stores).
-- All three FK columns have constraints, ensuring:
--   - Cannot reference a non-existent user, store, or permission template
--   - Must migrate all users off a template before deleting it (FK blocks deletion)
--   - Must clean up junction records before deleting a store
-- ─────────────────────────────────────────────
-- 关联表：将用户与特定门店内的权限模板关联。
-- 主键 = (user_id, store_id)，即每个用户在每个门店只能有一个权限模板
-- （但在不同门店可以有不同模板）。
-- 三个外键列均有约束，保证：
--   - 不能引用不存在的用户、门店或权限模板
--   - 删除权限模板前需先迁移所有关联用户（外键拦截）
--   - 删除门店前需先清理关联记录
-- =============================================

CREATE TABLE IF NOT EXISTS public.store_user_rights (

  -- User ID, FK to user_list
  -- 用户 ID，外键指向 user_list
  user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- Store ID, FK to store_list
  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- Permission template ID, FK to user_rights_templates
  -- 权限模板 ID，外键指向 user_rights_templates
  template_id integer NOT NULL REFERENCES public.user_rights_templates(template_id),

  -- Record creation timestamp
  -- 记录创建时间
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Last update timestamp (auto-refreshed by set_updated_at() trigger)
  -- 最后更新时间（由 set_updated_at() 触发器自动刷新）
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Composite PK: one user can have only one permission template per store
  -- 联合主键：同一用户在同一门店只能有一个权限模板
  CONSTRAINT store_user_rights_pkey PRIMARY KEY (user_id, store_id)
);

-- =============================================
-- Trigger: auto-refresh updated_at on every UPDATE
-- (reuses set_updated_at() created in 03_user_list)
-- 触发器：每次 UPDATE 自动刷新 updated_at
-- （复用 03_user_list 中创建的 set_updated_at()）
-- =============================================
DROP TRIGGER IF EXISTS trg_store_user_rights_updated_at ON public.store_user_rights;
CREATE TRIGGER trg_store_user_rights_updated_at
BEFORE UPDATE ON public.store_user_rights
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =============================================
-- Index: look up all user permissions for a given store
-- 索引：查询某门店下所有用户的权限
-- =============================================
CREATE INDEX IF NOT EXISTS idx_store_user_rights_store
  ON public.store_user_rights (store_id);

-- =============================================
-- Index: find which users reference a given template (useful before deleting a template)
-- 索引：查询某权限模板被哪些用户使用（删除模板前使用）
-- =============================================
CREATE INDEX IF NOT EXISTS idx_store_user_rights_template
  ON public.store_user_rights (template_id);
