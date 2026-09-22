-- Open Finance via Pluggy: conexões, contas e transações do banco, e o elo
-- entre uma transação do banco e um lançamento do Lastro ("o mês bate com o banco").
-- Tudo aqui é escrito só pelo servidor (edge functions com service role).

alter type public.tx_source add value if not exists 'bank';

-- Lançamento conferido com uma transação do banco.
alter table public.transactions add column if not exists bank_confirmed_at timestamptz;

create table public.bank_connections (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users on delete cascade,
  pluggy_item_id text not null unique,
  connector_name text not null,
  connector_logo text,
  status         text not null,           -- UPDATED | UPDATING | LOGIN_ERROR | OUTDATED | WAITING_USER_INPUT…
  error_message  text,
  last_synced_at timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

create table public.bank_accounts (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users on delete cascade,
  connection_id     uuid not null references public.bank_connections on delete cascade,
  pluggy_account_id text not null unique,
  type              text not null,        -- BANK | CREDIT
  subtype           text,
  name              text not null,
  number            text,
  balance_cents     bigint,
  card_id           uuid references public.cards on delete set null,  -- conta CREDIT ↔ cartão do Lastro
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

create table public.bank_transactions (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references auth.users on delete cascade,
  bank_account_id       uuid not null references public.bank_accounts on delete cascade,
  pluggy_transaction_id text not null unique,
  date                  date not null,
  description           text not null,
  amount_cents          bigint not null,  -- positivo = saiu dinheiro
  type                  text not null,    -- DEBIT | CREDIT
  category              text,
  merchant              text,
  status                text,             -- POSTED | PENDING
  transaction_id        uuid references public.transactions on delete set null,
  ignored_reason        text,             -- entrada, pagamento de fatura, mês fechado…
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz
);

create index bank_transactions_open_idx on public.bank_transactions (user_id)
  where transaction_id is null and ignored_reason is null and deleted_at is null;

do $$
declare t text;
begin
  foreach t in array array['bank_connections', 'bank_accounts', 'bank_transactions'] loop
    execute format('create trigger %I_updated_at before update on public.%I
                    for each row execute function public.set_updated_at()', t, t);
    execute format('create index %I_sync_idx on public.%I (user_id, updated_at)', t, t);
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy owner_read on public.%I for select to authenticated using (user_id = auth.uid())', t);
    execute format('revoke insert, update, delete on public.%I from anon, authenticated', t);
  end loop;
end $$;
