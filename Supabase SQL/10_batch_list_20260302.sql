-- =========================================
-- 10 · batch_list 营业批次表
-- =========================================
-- 依赖: 01_store_list (store_id FK)
--        03_user_list (opened_by_user_id / closed_by_user_id FK)
-- 被依赖: 11_shift_list (store_id, batch_id 复合 FK)
--
-- 每个门店的营业批次记录，一个门店同一时间只能有一个 open batch
-- 不支持软删除：批次是历史记录，关闭后永久保留

-- =========================================
-- 函数: assign_batch_id_per_store()
-- =========================================
-- 同一 store_id 下，batch_id 从 1 开始依次递增
-- 使用行级咨询锁阻止并发插入时产生重复编号
CREATE OR REPLACE FUNCTION public.assign_batch_id_per_store()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  next_bid int;
BEGIN
  IF NEW.store_id IS NULL THEN
    RAISE EXCEPTION 'store_id cannot be null';
  END IF;

  -- 咨询锁：命名空间 1002，避免和其他锁冲突
  PERFORM pg_advisory_xact_lock(1002, hashtext(NEW.store_id));

  SELECT COALESCE(MAX(batch_id), 0) + 1
    INTO next_bid
  FROM public.batch_list
  WHERE store_id = NEW.store_id;

  NEW.batch_id := next_bid;
  RETURN NEW;
END;
$$;

-- =========================================
-- 建表
-- =========================================
CREATE TABLE IF NOT EXISTS public.batch_list (

  -- 门店 ID，外键指向 store_list
  store_id text NOT NULL REFERENCES public.store_list(store_id),

  -- 批次编号，同一门店内从 1 开始自动递增，由触发器分配
  batch_id integer NOT NULL,

  -- 批次是否处于开启状态
  is_open boolean NOT NULL DEFAULT true,

  -- 批次开启时间
  opened_at timestamptz NOT NULL DEFAULT now(),

  -- 批次关闭时间；开启状态下应为 NULL
  closed_at timestamptz DEFAULT NULL,

  -- 开启批次的用户
  opened_by_user_id integer REFERENCES public.user_list(user_id),

  -- 关闭批次的用户
  closed_by_user_id integer REFERENCES public.user_list(user_id),

  -- 备注
  note text DEFAULT NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- 联合主键
  CONSTRAINT batch_list_pk PRIMARY KEY (store_id, batch_id),

  -- batch_id 应为正整数
  CONSTRAINT batch_list_batch_id_positive CHECK (batch_id > 0),

  -- 开关状态一致性：开启时 closed_at 应为空，关闭时应有值
  CONSTRAINT batch_list_open_close_consistency CHECK (
    (is_open = true  AND closed_at IS NULL)
    OR
    (is_open = false AND closed_at IS NOT NULL)
  )
);

-- =========================================
-- batch_id 自动分配触发器
-- =========================================
DROP TRIGGER IF EXISTS trg_batch_list_assign_id ON public.batch_list;
CREATE TRIGGER trg_batch_list_assign_id
BEFORE INSERT ON public.batch_list
FOR EACH ROW
EXECUTE FUNCTION public.assign_batch_id_per_store();

-- =========================================
-- 一个门店同时只能有一个 open batch
-- =========================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_batch_one_open_per_store
  ON public.batch_list (store_id)
  WHERE is_open = true;

-- =========================================
-- 常用查询：某店最近 batch
-- =========================================
CREATE INDEX IF NOT EXISTS idx_batch_store_opened_at
  ON public.batch_list (store_id, opened_at DESC);

-- =========================================
-- updated_at 自动刷新触发器
-- （复用 03_user_list 中创建的 public.set_updated_at()）
-- =========================================
DROP TRIGGER IF EXISTS trg_batch_list_updated_at ON public.batch_list;
CREATE TRIGGER trg_batch_list_updated_at
BEFORE UPDATE ON public.batch_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
