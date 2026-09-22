-- Dados de exemplo do protótipo (Lastro.dc.html): 11 categorias, 6 cartões,
-- 18 contas fixas, jan–ago fechados, setembro corrente, out–dez em planejamento.
--
-- Chamado pelo app em builds de desenvolvimento (e pelo onboarding "Trazer as
-- 18 contas fixas" enquanto o importador de planilha não existe).
-- Só roda para uma conta vazia.

create or replace function public._seed_demo(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  y        int := 2026;
  cur      date := make_date(y, 9, 1);
  today    int := 21;
  hist     int[] := array[82000, -34000, 121000, 41000, -89000, 15000, 62000, -21000];  -- sobra jan–ago
  c        record;
  mi       int;
  m        date;
  spent    bigint;
  saiu     bigint;
  v_cat   jsonb := '{}';
  v_card   jsonb := '{}';
  v_bill   jsonb := '{}';
  v        jsonb;
  new_id   uuid;
begin
  if exists (select 1 from categories where user_id = p_user) then
    raise exception 'conta já tem dados' using errcode = 'unique_violation';
  end if;

  insert into profiles (user_id) values (p_user) on conflict do nothing;
  update profiles set monthly_income_cents = 2310000, safety_floor_cents = 300000,
                      approval_threshold_cents = 100000
  where user_id = p_user;

  -- categorias ─────────────────────────────────────────────────
  insert into categories (user_id, slug, name, hue, nature, default_budget_cents, symbol, position)
  select p_user, e.v->>0, e.v->>1, (e.v->>2)::smallint, (e.v->>3)::category_nature,
         (e.v->>4)::bigint, e.v->>5, e.pos - 1
  from jsonb_array_elements('[
    ["moradia","Moradia",265,"fixo",452233,"house"],
    ["mercado","Mercado",160,"variavel",80000,"cart"],
    ["rango","Rango & Café",75,"variavel",60000,"cup.and.saucer"],
    ["transporte","Transporte",225,"variavel",40000,"car"],
    ["saude","Saúde",20,"fixo",120000,"heart"],
    ["mesadas","Mesadas",320,"fixo",170000,"gift"],
    ["igreja","Igreja & Ofertas",290,"fixo",320000,"hands.and.sparkles"],
    ["familia","Família",195,"fixo",209000,"person.2"],
    ["lazer","Lazer & Assinaturas",345,"fixo",48000,"music.note"],
    ["dividas","Dívidas",45,"parcelado",611000,"doc.plaintext"],
    ["imprevistos","Imprevistos",120,"reserva",30000,"umbrella"]]'::jsonb) with ordinality as e(v, pos);

  select jsonb_object_agg(slug, id) into v_cat from categories where user_id = p_user;

  -- cartões ────────────────────────────────────────────────────
  insert into cards (user_id, name, subtitle, hue, limit_cents, closing_day, due_day, position)
  select p_user, e.v->>1, e.v->>2, (e.v->>3)::smallint, (e.v->>4)::bigint,
         (e.v->>5)::smallint, (e.v->>6)::smallint, e.pos - 1
  from jsonb_array_elements('[
    ["nubank","Nubank","final 4821",305,1400000,28,5],
    ["click","Itaú Click","final 1190",48,1200000,15,22],
    ["uniclass","Itaú Uniclass","final 7733",258,2000000,15,22],
    ["lorena","Itaú Lorena","adicional · 7734",350,400000,15,22],
    ["bradesco","Bradesco","final 0562",22,900000,20,28],
    ["atacadao","Atacadão","final 3308",150,300000,25,2]]'::jsonb) with ordinality as e(v, pos);

  select jsonb_object_agg(k.slug, cd.id) into v_card
  from cards cd join (values ('nubank','Nubank'),('click','Itaú Click'),('uniclass','Itaú Uniclass'),
                             ('lorena','Itaú Lorena'),('bradesco','Bradesco'),('atacadao','Atacadão')) k(slug, name)
    on k.name = cd.name
  where cd.user_id = p_user;

  -- contas fixas ───────────────────────────────────────────────
  for v in select * from jsonb_array_elements('[
    ["aluguel","Aluguel","moradia",5,320000,false,true,"pix","aluguel@imobsol.com.br"],
    ["condominio","Condomínio","moradia",8,45543,false,false,"boleto",null],
    ["luz","Luz","moradia",10,41250,true,true,"boleto",null],
    ["agua","Água","moradia",12,13820,true,true,"boleto",null],
    ["gas","Gás","moradia",15,9640,true,false,"boleto",null],
    ["net","Internet e telefone","moradia",18,21980,false,true,"debito",null],
    ["terapia","Terapia","saude",7,80000,false,false,"pix","clinica.alma@pix.com"],
    ["medicacao","Medicação","saude",10,40000,false,false,"debito",null],
    ["mes_lorena","Mesada da Lorena","mesadas",1,120000,false,true,"pix","lorena@email.com"],
    ["mes_minha","Minha mesada","mesadas",1,50000,false,true,"pix",null],
    ["dizimo","Dízimo","igreja",2,231000,false,true,"pix","igreja@pix.org.br"],
    ["ofertas","Ofertas","igreja",14,89000,false,false,"pix",null],
    ["matheus","Ajuda ao Matheus","familia",21,209000,false,true,"pix","matheus.s@email.com"],
    ["canto","Aula de canto","lazer",22,36000,false,true,"pix",null],
    ["streaming","Streaming","lazer",27,12000,false,true,"debito",null],
    ["carro","Parcela do carro","dividas",20,238000,false,true,"boleto",null],
    ["nubank_acordo","Acordo Nubank","dividas",25,273000,false,true,"boleto",null],
    ["igor","Acordo Igor","dividas",28,100000,false,false,"pix",null]]'::jsonb)
  loop
    insert into bills (user_id, name, category_id, due_day, amount_cents, is_variable, autopay, method, pix_key)
    values (p_user, v->>1, (v_cat->>(v->>2))::uuid, (v->>3)::smallint, (v->>4)::bigint,
            (v->>5)::boolean, (v->>6)::boolean, (v->>7)::pay_method, v->>8)
    returning id into new_id;
    v_bill := v_bill || jsonb_build_object(v->>0, new_id);
  end loop;

  -- jan–ago: meses fechados, um lançamento consolidado por categoria ─
  -- (mesma fórmula do protótipo: variáveis oscilam entre 72% e 119% do orçamento)
  for mi in 0..7 loop
    m := make_date(y, mi + 1, 1);
    saiu := 0;
    for c in select id, nature, default_budget_cents, position from categories
             where user_id = p_user order by position loop
      spent := case when c.nature in ('variavel', 'reserva')
                    then round(c.default_budget_cents * (72 + ((c.position * 37 + mi * 53) % 48)) / 100.0)
                    else c.default_budget_cents end;
      saiu := saiu + spent;
      insert into month_budgets (user_id, month, category_id, amount_cents)
      values (p_user, m, c.id, c.default_budget_cents);
      insert into transactions (user_id, month, day, description, category_id, amount_cents,
                                method, confirmed, kind, source)
      values (p_user, m, 28, 'Consolidado da planilha', c.id, spent, 'pix', true,
              case when c.nature in ('variavel', 'reserva') then 'variavel'
                   when c.nature = 'parcelado' then 'parcela' else 'fixa' end::tx_kind,
              'import');
    end loop;
    insert into months (user_id, month, status, income_cents, closed_at)
    values (p_user, m, 'closed', saiu + hist[mi + 1], (m + interval '1 month')::timestamptz);
  end loop;

  -- setembro: corrente ─────────────────────────────────────────
  insert into months (user_id, month, status, income_cents) values (p_user, cur, 'open', 2310000);
  perform _open_month(p_user, cur);

  update transactions t set
    confirmed = (t.day <= today and t.bill_id not in ((v_bill->>'gas')::uuid, (v_bill->>'matheus')::uuid)),
    estimated = (t.bill_id = (v_bill->>'gas')::uuid)
  where t.user_id = p_user and t.month = cur and t.bill_id is not null;

  insert into transactions (user_id, month, day, description, category_id, amount_cents,
                            method, card_id, confirmed, kind, source)
  select p_user, cur, (e.v->>2)::smallint, e.v->>0, (v_cat->>(e.v->>1))::uuid, (e.v->>3)::bigint,
         (e.v->>4)::pay_method, (v_card->>(e.v->>5))::uuid, (e.v->>6)::boolean, 'variavel', 'manual'
  from jsonb_array_elements('[
    ["Atacadão","mercado",6,31240,"cartao","atacadao",true],
    ["Pão de Açúcar","mercado",14,18690,"cartao","click",true],
    ["Hortifruti","mercado",18,4870,"pix",null,true],
    ["Mercadinho","mercado",20,9230,"debito",null,true],
    ["iFood","rango",3,3890,"cartao","nubank",true],
    ["Padaria","rango",5,1450,"debito",null,true],
    ["Café","rango",6,1200,"debito",null,true],
    ["iFood","rango",9,4680,"cartao","nubank",true],
    ["Padaria","rango",11,2240,"pix",null,true],
    ["iFood","rango",13,4190,"cartao","nubank",true],
    ["Café","rango",16,950,"debito",null,true],
    ["iFood","rango",17,4990,"cartao","nubank",true],
    ["Padaria","rango",19,1860,"pix",null,true],
    ["iFood","rango",20,4490,"cartao","nubank",true],
    ["Café","rango",21,1100,"debito",null,true],
    ["iFood","rango",21,3650,"cartao","nubank",false],
    ["Uber","transporte",4,2340,"cartao","uniclass",true],
    ["Gasolina","transporte",8,18000,"cartao","bradesco",true],
    ["Uber","transporte",15,3120,"cartao","uniclass",true],
    ["Uber","transporte",19,1890,"cartao","uniclass",true],
    ["99","transporte",21,1670,"cartao","uniclass",false],
    ["Chaveiro","imprevistos",12,12000,"pix",null,true],
    ["Cinema","lazer",13,6400,"cartao","nubank",true],
    ["Farmácia","saude",16,3780,"pix",null,true]]'::jsonb) as e(v);

  insert into card_carryovers (user_id, card_id, month, amount_cents)
  select p_user, (v_card->>k)::uuid, cur, a
  from (values ('nubank',214060),('click',86020),('uniclass',142000),('lorena',38050),('bradesco',54000)) x(k, a);

  -- out–dez: planejamento (fixas já copiadas) ─────────────────
  for mi in 10..12 loop
    insert into months (user_id, month, status, income_cents)
    values (p_user, make_date(y, mi, 1), 'planning', 2310000);
    perform _open_month(p_user, make_date(y, mi, 1));
  end loop;

  -- dívidas, metas, recibos ───────────────────────────────────
  insert into debts (user_id, name, description, bill_id, installment_cents, installments_total,
                     installments_paid, paid_cents, position) values
    (p_user, 'Carro',  'financiamento',               (v_bill->>'carro')::uuid,         238000, 48, 23, 23 * 238000, 0),
    (p_user, 'Nubank', 'rotativo renegociado',        (v_bill->>'nubank_acordo')::uuid, 273000,  3,  1, 273000,      1),
    (p_user, 'Igor',   'acordo',                      (v_bill->>'igor')::uuid,          100000,  4,  2, 200000,      2),
    (p_user, 'C&A',    'quitado em julho',            null,                                   0,  6,  6, 114000,      3);

  insert into goals (user_id, kind, name, description, target_cents, saved_cents, hue, position) values
    (p_user, 'emergency', 'Reserva de emergência', '6 meses de custo fixo', null, 3470000, 155, 0),
    (p_user, 'custom',    'Quitar o Nubank',       '2 parcelas restantes',  819000, 273000, 262, 1),
    (p_user, 'custom',    'Viagem de julho',       'R$ 400 por mês',        800000, 240000,  55, 2);

  insert into receipts (user_id, merchant, origin_label, source, amount_cents, category_id, card_id, captured_at) values
    (p_user, 'iFood',    'Compartilhado do iFood · 20:14', 'share', 4290, (v_cat->>'rango')::uuid,      (v_card->>'nubank')::uuid,   '2026-09-21 20:14-03'),
    (p_user, 'Uber',     'Compartilhado do Uber · 18:02',  'share', 2760, (v_cat->>'transporte')::uuid, (v_card->>'uniclass')::uuid, '2026-09-21 18:02-03'),
    (p_user, 'Drogasil', 'Cupom escaneado · ontem',        'scan',  6430, (v_cat->>'saude')::uuid,      null,                          '2026-09-20 12:00-03');
end $$;

revoke all on function public._seed_demo(uuid) from public, anon, authenticated;

create or replace function public.seed_demo() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'não autenticado' using errcode = 'insufficient_privilege'; end if;
  perform _seed_demo(auth.uid());
end $$;
