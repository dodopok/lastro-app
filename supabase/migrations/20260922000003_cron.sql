-- "Todo dia 1 o mês novo já nasce com ela": abre o mês corrente e o seguinte
-- (planejamento) de todo mundo. Roda 03:00 UTC (meia-noite em Brasília).
-- pg_cron existe no Supabase; em Postgres puro (testes) esta migration é no-op.

create or replace function public._open_months_for_everyone() returns void
language plpgsql security definer set search_path = public as $$
declare p record;
begin
  for p in select user_id from profiles loop
    perform _open_month(p.user_id, current_month_for(p.user_id));
    perform _open_month(p.user_id, (current_month_for(p.user_id) + interval '1 month')::date);
  end loop;
end $$;

revoke all on function public._open_months_for_everyone() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('lastro-open-months', '0 3 * * *', 'select public._open_months_for_everyone()');
  else
    raise notice 'pg_cron indisponível: agendamento ignorado';
  end if;
end $$;
