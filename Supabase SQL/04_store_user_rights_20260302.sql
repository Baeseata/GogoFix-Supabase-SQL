-- =========================================
-- 04 · store_user_rights 门店-用户-权限关联表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        03_user_list (user_id FK)
--        02_user_rights_templates (template_id FK)
-- 被依赖: 无
--
-- 记录某个用户在某个门店拥有哪个权限模板
-- 下列均有外键约束，数据库层面保证：
--   - 不能引用不存在的用户、门店、权限模板
--   - 删除权限模板前需先迁移所有关联用户（外键拦截）
--   - 删除门店前需先清理关联记录

CREATE TABLE IF NOT EXISTS public.store_user_rights (

  -- 用户 ID，外键指向 user_list
  user_id integer NOT NULL REFERENCES public.user_list(user_id),

  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 权限模板 ID，外键指向 user_rights_templates
  template_id integer NOT NULL REFERENCES public.user_rights_templates(template_id),

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- 联合主键：同一用户在同一门店只能有一个权限模板
  CONSTRAINT store_user_rights_pkey PRIMARY KEY (user_id, store_id)
);

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_store_user_rights_updated_at ON public.store_user_rights;
CREATE TRIGGER trg_store_user_rights_updated_at
BEFORE UPDATE ON public.store_user_rights
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =========================================
-- 索引
-- =========================================

-- 查询门店的所有用户权限
CREATE INDEX IF NOT EXISTS idx_store_user_rights_store
  ON public.store_user_rights (store_id);

-- 查询权限模板被哪些用户使用（删除模板前查询）
CREATE INDEX IF NOT EXISTS idx_store_user_rights_template
  ON public.store_user_rights (template_id);
