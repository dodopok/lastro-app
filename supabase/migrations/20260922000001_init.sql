-- Lastro · schema inicial
--
-- Convenções
--   * Dinheiro sempre em centavos (bigint). Nada de float.
--   * Mês = primeiro dia do mês (date). Ex.: 2026-09-01.
--   * Toda tabela do usuário tem user_id + RLS "só o dono".
--   * ids são UUID gerados no aparelho (offline-first): o upsert é idempotente.
--   * updated_at é sempre do servidor (trigger); deleted_at é soft delete.
--     O app sincroniza puxando "updated_at > cursor" (inclui apagados).

-- ─────────────────────────────────────────────────────────────── tipos

create type public.category_nature as enum ('fixo', 'variavel', 'parcelado', 'reserva');
create type public.pay_method      as enum ('pix', 'boleto', 'debito', 'cartao');
create type public.tx_kind         as enum ('fixa', 'parcela', 'variavel');
create type public.tx_source       as enum ('manual', 'scan', 'share', 'bill', 'import');
create type public.month_status    as enum ('planning', 'open', 'closed');
create type public.receipt_status  as enum ('pending', 'saved', 'discarded');
create type public.goal_kind       as enum ('emergency', 'custom');
create type public.payment_status  as enum (
  'scheduled',          -- criado pelo piloto, aguardando o dia
  'awaiting_approval',  -- acima do limite: precisa de Face ID no app
  'processing',         -- enviado ao provedor
  'paid',
  'failed',
  'blocked'             -- trava de segurança: saldo abaixo do mínimo
);

-- ─────────────────────────────────────────────────────────────── helpers

create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ─────────────────────────────────────────────────────────────── perfil

create table public.profiles (
  user_id                  uuid primary key references auth.users on delete cascade,
  display_name             text,
  timezone                 text   not null default 'America/Sao_Paulo',
  monthly_income_cents     bigint not null default 0 check (monthly_income_cents >= 0),
  safety_floor_cents       bigint not null default 300000 check (safety_floor_cents >= 0),  -- trava
  approval_threshold_cents bigint not null default 100000 check (approval_threshold_cents >= 0), -- Face ID acima disto
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

-- Mês corrente no fuso do usuário.
create or replace function public.current_month_for(p_user uuid) returns date
language sql stable as $$
  select date_trunc('month', now() at time zone coalesce(
           (select timezone from public.profiles where user_id = p_user),
           'America/Sao_Paulo'))::date
$$;

-- ─────────────────────────────────────────────────────────────── cadastro

create table public.categories (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null default auth.uid() references auth.users on delete cascade,
  slug                 text not null,
  name                 text not null,
  hue                  smallint not null check (hue between 0 and 360),
  nature               public.category_nature not null,
  default_budget_cents bigint not null default 0 check (default_budget_cents >= 0),
  symbol               text not null default 'circle',  -- SF Symbol
  position             smallint not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  unique (user_id, slug)
);

create table public.cards (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  name        text not null,
  subtitle    text,
  hue         smallint not null check (hue between 0 and 360),
  limit_cents bigint not null default 0 check (limit_cents >= 0),
  closing_day smallint not null check (closing_day between 1 and 31),
  due_day     smallint not null check (due_day between 1 and 31),
  position    smallint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- Parcelas e saldo de meses anteriores que já estão na fatura do mês.
create table public.card_carryovers (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  card_id      uuid not null references public.cards on delete cascade,
  month        date not null check (extract(day from month) = 1),
  amount_cents bigint not null check (amount_cents >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (card_id, month)
);

-- Contas fixas: cadastra uma vez, todo mês novo nasce com elas.
create table public.bills (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  name         text not null check (length(trim(name)) > 0),
  category_id  uuid not null references public.categories,
  due_day      smallint not null check (due_day between 1 and 28),
  amount_cents bigint not null check (amount_cents > 0),
  is_variable  boolean not null default false,  -- estimado pela média dos 3 últimos meses
  autopay      boolean not null default false,  -- piloto automático
  method       public.pay_method not null default 'pix' check (method <> 'cartao'),
  pix_key      text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

create table public.debts (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null default auth.uid() references auth.users on delete cascade,
  name               text not null,
  description        text,
  bill_id            uuid references public.bills on delete set null,
  installment_cents  bigint not null default 0 check (installment_cents >= 0),
  installments_total smallint not null check (installments_total > 0),
  installments_paid  smallint not null default 0,
  paid_cents         bigint not null default 0 check (paid_cents >= 0),
  position           smallint not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  check (installments_paid between 0 and installments_total)
);

create table public.goals (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  kind         public.goal_kind not null default 'custom',
  name         text not null,
  description  text,
  target_cents bigint check (target_cents > 0),  -- null em 'emergency': 6× custo fixo
  saved_cents  bigint not null default 0 check (saved_cents >= 0),
  hue          smallint not null default 155 check (hue between 0 and 360),
  position     smallint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  check (kind = 'emergency' or target_cents is not null)
);

-- ─────────────────────────────────────────────────────────────── meses

create table public.months (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  month        date not null check (extract(day from month) = 1),
  status       public.month_status not null,
  income_cents bigint not null default 0 check (income_cents >= 0),
  closed_at    timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (user_id, month)
);

create table public.month_budgets (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  month        date not null check (extract(day from month) = 1),
  category_id  uuid not null references public.categories on delete cascade,
  amount_cents bigint not null check (amount_cents >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (user_id, month, category_id)
);

-- "Item só deste mês" no planejamento (IPVA, presente, viagem…).
create table public.month_extras (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  month        date not null check (extract(day from month) = 1),
  name         text not null,
  amount_cents bigint not null check (amount_cents >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

-- ─────────────────────────────────────────────────────────────── lançamentos

create table public.transactions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  month        date not null check (extract(day from month) = 1),
  day          smallint not null check (day between 1 and 31),
  description  text not null,
  category_id  uuid not null references public.categories,
  amount_cents bigint not null check (amount_cents > 0),
  method       public.pay_method not null,
  card_id      uuid references public.cards,
  confirmed    boolean not null default false,
  kind         public.tx_kind not null default 'variavel',
  source       public.tx_source not null default 'manual',
  bill_id      uuid references public.bills on delete set null,
  estimated    boolean not null default false,  -- "~" na UI: conta variável ainda sem valor real
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  check ((method = 'cartao') = (card_id is not null))
);

-- Uma ocorrência de cada conta fixa por mês: torna open_month idempotente.
create unique index transactions_bill_month_uq
  on public.transactions (bill_id, month) where bill_id is not null and deleted_at is null;
create index transactions_user_month_idx on public.transactions (user_id, month) where deleted_at is null;

-- Recibos: chegam pela extensão de compartilhar e pelo scan.
create table public.receipts (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users on delete cascade,
  merchant       text not null,
  origin_label   text not null,  -- "Compartilhado do iFood · 20:14"
  source         public.tx_source not null default 'share' check (source in ('share', 'scan')),
  amount_cents   bigint not null check (amount_cents > 0),
  category_id    uuid references public.categories,
  card_id        uuid references public.cards,  -- null = Pix/débito
  captured_at    timestamptz not null default now(),
  status         public.receipt_status not null default 'pending',
  transaction_id uuid references public.transactions on delete set null,
  image_path     text,  -- storage: receipts/<user_id>/<id>.jpg
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

-- ─────────────────────────────────────────────────────────────── piloto

-- Escrito só pelo servidor (edge functions com service role). O app só lê.
create table public.payments (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users on delete cascade,
  bill_id           uuid references public.bills on delete set null,
  transaction_id    uuid references public.transactions on delete set null,
  amount_cents      bigint not null check (amount_cents > 0),
  method            public.pay_method not null check (method in ('pix', 'boleto')),
  destination       text not null,  -- chave Pix ou linha digitável
  scheduled_for     date not null,
  status            public.payment_status not null default 'scheduled',
  requires_approval boolean not null default false,
  approved_at       timestamptz,
  provider          text not null default 'sandbox',
  provider_ref      text,
  failure_reason    text,
  idempotency_key   text not null unique,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- Nunca dois pagamentos vivos para o mesmo lançamento (cron e app podem correr juntos).
create unique index payments_live_transaction_uq on public.payments (transaction_id)
  where transaction_id is not null and status in ('scheduled', 'awaiting_approval', 'processing', 'paid');

-- ─────────────────────────────────────────────────────────────── triggers updated_at

do $$
declare t text;
begin
  foreach t in array array['profiles','categories','cards','card_carryovers','bills','debts','goals',
                           'months','month_budgets','month_extras','transactions','receipts','payments']
  loop
    execute format('create trigger %I_updated_at before update on public.%I
                    for each row execute function public.set_updated_at()', t, t);
    execute format('create index %I_sync_idx on public.%I (user_id, updated_at)', t, t);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────── RLS

do $$
declare t text;
begin
  foreach t in array array['profiles','categories','cards','card_carryovers','bills','debts','goals',
                           'months','month_budgets','month_extras','transactions','receipts']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy owner_all on public.%I for all to authenticated
                    using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;

alter table public.payments enable row level security;
create policy owner_read on public.payments for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.payments from anon, authenticated;

-- ─────────────────────────────────────────────────────────────── regras de negócio

-- Mês fechado é só leitura.
create or replace function public.guard_closed_month() returns trigger
language plpgsql as $$
declare
  v_user  uuid := coalesce(new.user_id, old.user_id);
  v_month date := coalesce(new.month, old.month);
begin
  if exists (select 1 from public.months
             where user_id = v_user and month = v_month and status = 'closed') then
    raise exception 'mês % está fechado', to_char(v_month, 'YYYY-MM') using errcode = 'check_violation';
  end if;
  if tg_op = 'UPDATE' and old.month <> new.month and exists (
       select 1 from public.months where user_id = v_user and month = old.month and status = 'closed') then
    raise exception 'mês % está fechado', to_char(old.month, 'YYYY-MM') using errcode = 'check_violation';
  end if;
  return coalesce(new, old);
end $$;

create trigger transactions_guard_closed before insert or update or delete on public.transactions
  for each row execute function public.guard_closed_month();
create trigger month_budgets_guard_closed before insert or update or delete on public.month_budgets
  for each row execute function public.guard_closed_month();
create trigger month_extras_guard_closed before insert or update or delete on public.month_extras
  for each row execute function public.guard_closed_month();

-- Perfil nasce com o usuário.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Valor estimado de uma conta variável: média dos 3 últimos meses (confirmados).
create or replace function public.estimate_bill_cents(p_bill uuid, p_month date) returns bigint
language sql stable as $$
  select coalesce(
    (select round(avg(amount_cents))::bigint from (
       select amount_cents from public.transactions
       where bill_id = p_bill and confirmed and deleted_at is null
         and month < p_month and month >= p_month - interval '3 months'
       order by month desc limit 3) last3),
    (select amount_cents from public.bills where id = p_bill))
$$;

-- Abre um mês: orçamento copiado do mês anterior (ou do padrão das categorias)
-- e uma ocorrência de cada conta fixa ativa. Idempotente.
create or replace function public._open_month(p_user uuid, p_month date) returns public.months
language plpgsql security definer set search_path = public as $$
declare
  v_month date := date_trunc('month', p_month)::date;
  v_prev  date := (date_trunc('month', p_month) - interval '1 month')::date;
  v_row   public.months;
begin
  insert into months (user_id, month, status, income_cents)
  values (p_user, v_month,
          case when v_month <= current_month_for(p_user) then 'open' else 'planning' end::month_status,
          coalesce((select income_cents from months where user_id = p_user and month = v_prev),
                   (select monthly_income_cents from profiles where user_id = p_user), 0))
  on conflict (user_id, month) do nothing;

  select * into v_row from months where user_id = p_user and month = v_month;
  if v_row.status = 'closed' then
    return v_row;
  end if;

  insert into month_budgets (user_id, month, category_id, amount_cents)
  select p_user, v_month, c.id,
         coalesce((select mb.amount_cents from month_budgets mb
                   where mb.user_id = p_user and mb.month = v_prev and mb.category_id = c.id
                     and mb.deleted_at is null),
                  c.default_budget_cents)
  from categories c
  where c.user_id = p_user and c.deleted_at is null
  on conflict (user_id, month, category_id) do nothing;

  insert into transactions (user_id, month, day, description, category_id, amount_cents,
                            method, confirmed, kind, source, bill_id, estimated)
  select p_user, v_month, b.due_day, b.name, b.category_id,
         case when b.is_variable then estimate_bill_cents(b.id, v_month) else b.amount_cents end,
         b.method, false,
         case when c.nature = 'parcelado' then 'parcela' else 'fixa' end::tx_kind,
         'bill', b.id, b.is_variable
  from bills b join categories c on c.id = b.category_id
  where b.user_id = p_user and b.deleted_at is null
    and not exists (select 1 from transactions t
                    where t.bill_id = b.id and t.month = v_month and t.deleted_at is null);

  return v_row;
end $$;

revoke all on function public._open_month(uuid, date) from public, anon, authenticated;

create or replace function public.open_month(p_month date) returns public.months
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'não autenticado' using errcode = 'insufficient_privilege'; end if;
  return _open_month(auth.uid(), p_month);
end $$;

create or replace function public.close_month(p_month date) returns public.months
language sql security invoker as $$
  update public.months set status = 'closed', closed_at = now()
  where user_id = auth.uid() and month = date_trunc('month', p_month)::date and status = 'open'
  returning *
$$;

-- "Alterações valem de outubro em diante": editar uma conta fixa atualiza as
-- ocorrências ainda não confirmadas dos meses seguintes. Meses fechados e o
-- corrente ficam como estão. Apagar a conta tira as ocorrências futuras.
create or replace function public.propagate_bill_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    update transactions set deleted_at = now()
    where bill_id = new.id and not confirmed and deleted_at is null
      and month > current_month_for(new.user_id);
    return new;
  end if;

  update transactions t set
    description  = new.name,
    day          = new.due_day,
    category_id  = new.category_id,
    method       = new.method,
    estimated    = new.is_variable,
    amount_cents = case when new.is_variable then estimate_bill_cents(new.id, t.month) else new.amount_cents end
  where t.bill_id = new.id and not t.confirmed and t.deleted_at is null
    and t.month > current_month_for(new.user_id)
    and exists (select 1 from months m where m.user_id = t.user_id and m.month = t.month and m.status <> 'closed');
  return new;
end $$;

create trigger bills_propagate after update on public.bills
  for each row when (old is distinct from new) execute function public.propagate_bill_change();

-- Saldo confirmado do mês = renda − tudo que já foi confirmado. É o que a trava olha.
create or replace function public.confirmed_balance_cents(p_user uuid, p_month date) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce((select income_cents from months where user_id = p_user and month = p_month), 0)
       - coalesce((select sum(amount_cents) from transactions
                   where user_id = p_user and month = p_month and confirmed and deleted_at is null), 0)
$$;

revoke all on function public.confirmed_balance_cents(uuid, date) from public, anon, authenticated;
