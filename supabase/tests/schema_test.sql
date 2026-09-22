-- Testes do schema. Rodar com supabase/tests/run.sh (Postgres local).
\set ON_ERROR_STOP on
\o /dev/null

create or replace function pg_temp.eq(label text, got anyelement, want anyelement) returns void
language plpgsql as $$
begin
  if got is distinct from want then
    raise exception 'FALHOU %: got=% want=%', label, got, want;
  end if;
  raise notice 'ok  %', label;
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'eu@lastro.app'),
  ('00000000-0000-0000-0000-00000000000b', 'outro@lastro.app');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

select public.seed_demo();

-- ── seed ────────────────────────────────────────────────────────────
select pg_temp.eq('11 categorias', (select count(*) from categories), 11::bigint);
select pg_temp.eq('6 cartões',     (select count(*) from cards), 6::bigint);
select pg_temp.eq('18 fixas',      (select count(*) from bills), 18::bigint);
select pg_temp.eq('12 meses',      (select count(*) from months), 12::bigint);
select pg_temp.eq('total das fixas R$ 19.302,33',
  (select sum(amount_cents) from bills), 1930233::numeric);
select pg_temp.eq('setembro nasce com as 18 fixas',
  (select count(*) from transactions where month = '2026-09-01' and bill_id is not null), 18::bigint);
select pg_temp.eq('outubro também',
  (select count(*) from transactions where month = '2026-10-01' and bill_id is not null), 18::bigint);
select pg_temp.eq('setembro: 6 fixas pendentes (gás, matheus e as que vencem depois do dia 21)',
  (select count(*) from transactions where month = '2026-09-01' and bill_id is not null and not confirmed),
  (select count(*) from bills where due_day > 21 or name in ('Gás', 'Ajuda ao Matheus')));
select pg_temp.eq('gás é o único estimado',
  (select string_agg(description, ',') from transactions where month = '2026-09-01' and estimated), 'Gás');

-- Histórico: sobra de agosto = −R$ 210
select pg_temp.eq('sobra de agosto',
  (select m.income_cents - sum(t.amount_cents) from months m
   join transactions t on t.month = m.month where m.month = '2026-08-01' group by m.income_cents),
  -21000::numeric);

-- Sobra prevista de setembro (mesma conta do protótipo: renda − Σ max(orçamento, gasto))
select pg_temp.eq('sobra prevista de setembro',
  (select 2310000 - sum(greatest(b.amount_cents, coalesce(s.spent, 0)))
   from month_budgets b
   left join (select category_id, sum(amount_cents) spent from transactions
              where month = '2026-09-01' and deleted_at is null group by category_id) s
     on s.category_id = b.category_id
   where b.month = '2026-09-01'),
  159587::numeric);

-- ── idempotência ────────────────────────────────────────────────────
select public.open_month('2026-09-01');
select public.open_month('2026-10-15');
select pg_temp.eq('open_month não duplica',
  (select count(*) from transactions where month = '2026-10-01' and bill_id is not null), 18::bigint);

-- ── mês fechado é só leitura ───────────────────────────────────────
do $$ begin
  update transactions set amount_cents = 1 where month = '2026-08-01';
  raise exception 'FALHOU: editou mês fechado';
exception when check_violation then raise notice 'ok  mês fechado bloqueia edição';
end $$;

-- ── editar conta fixa vale "de outubro em diante" ──────────────────
update bills set amount_cents = 350000 where name = 'Aluguel';
select pg_temp.eq('aluguel de setembro intacto',
  (select amount_cents from transactions where month = '2026-09-01' and description = 'Aluguel'), 320000::bigint);
select pg_temp.eq('aluguel de outubro atualizado',
  (select amount_cents from transactions where month = '2026-10-01' and description = 'Aluguel'), 350000::bigint);

update bills set deleted_at = now() where name = 'Streaming';
select pg_temp.eq('apagar fixa tira os meses futuros',
  (select count(*) from transactions where month > '2026-09-01' and description = 'Streaming' and deleted_at is null),
  0::bigint);
select pg_temp.eq('mas mantém setembro',
  (select count(*) from transactions where month = '2026-09-01' and description = 'Streaming' and deleted_at is null),
  1::bigint);

-- ── RLS ─────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select pg_temp.eq('outro usuário não vê nada', (select count(*) from transactions), 0::bigint);
do $$ declare blocked boolean := false; begin
  begin
    insert into transactions (user_id, month, day, description, category_id, amount_cents, method)
    select '00000000-0000-0000-0000-00000000000a', '2026-09-01', 1, 'x', gen_random_uuid(), 1, 'pix';
  exception when insufficient_privilege then blocked := true;
  end;
  if not blocked then raise exception 'FALHOU: escreveu na conta de outro'; end if;
  raise notice 'ok  RLS bloqueia escrita cruzada';
end $$;

-- ── payments: só leitura para o app ────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
do $$ begin
  insert into payments (user_id, amount_cents, method, destination, scheduled_for, idempotency_key)
  values (auth.uid(), 100, 'pix', 'x', current_date, 'k');
  raise exception 'FALHOU: app inseriu pagamento';
exception when insufficient_privilege then raise notice 'ok  app não cria pagamento';
end $$;

reset role;
insert into payments (user_id, transaction_id, amount_cents, method, destination, scheduled_for, idempotency_key, status)
select user_id, id, amount_cents, 'pix', 'matheus.s@email.com', '2026-09-21', 'bill:x', 'awaiting_approval'
from transactions where description = 'Ajuda ao Matheus' and month = '2026-09-01';
do $$ begin
  insert into payments (user_id, transaction_id, amount_cents, method, destination, scheduled_for, idempotency_key)
  select user_id, transaction_id, amount_cents, 'pix', destination, scheduled_for, 'app:y' from payments;
  raise exception 'FALHOU: dois pagamentos para o mesmo lançamento';
exception when unique_violation then raise notice 'ok  um pagamento vivo por lançamento';
end $$;

select pg_temp.eq('saldo confirmado de setembro (trava)',
  public.confirmed_balance_cents('00000000-0000-0000-0000-00000000000a', '2026-09-01') > 300000, true);

\o
\echo 'TODOS OS TESTES PASSARAM'
