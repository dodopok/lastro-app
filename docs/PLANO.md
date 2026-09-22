# Plano do Lastro

App iOS de orçamento pessoal: SwiftUI + Liquid Glass (iOS 26), com Supabase por
trás. O design de referência está em [`docs/design/Lastro.dc.html`](design/Lastro.dc.html)
(o protótipo navegável) e a conversa que levou a ele em
[`docs/design/conversa-design.md`](design/conversa-design.md).

## Precisa de backend?

**Para o núcleo, não. Para duas funcionalidades do design, sim.** Lançar, confirmar,
planejar, contas fixas, cartões, histórico, recibos e scan funcionam só no
aparelho. O backend é obrigatório para:

| Funcionalidade | Por que precisa de servidor |
| --- | --- |
| **Piloto automático** (pagar Pix/boleto sozinho) | Credenciais e certificado do provedor de pagamento nunca podem ficar no app. A trava de segurança e o limite do Face ID precisam ser verificados por quem move o dinheiro. O pagamento roda no horário, com o app fechado. |
| **Conectar banco** (Pluggy) | O `clientSecret` gera o connect token no servidor, e os webhooks de novas transações precisam de um endpoint. |

A decisão foi usar **Supabase desde já**, com o app **offline-first**. Isso dá sync
entre aparelhos, dados sobrevivendo à troca de celular e o caminho pronto para as
duas funcionalidades acima.

## Arquitetura

```
┌──────────────── iPhone ────────────────┐        ┌────────────── Supabase ──────────────┐
│ SwiftUI (telas)                         │        │ Postgres + RLS (só o dono)           │
│   ↑ lê             ↓ ações              │        │   open_month() · seed_demo()         │
│ AppStore (@Observable, MainActor)       │        │   triggers: mês fechado é só leitura,│
│   ↑ Ledger (LastroKit, valor puro)      │  HTTPS │   fixas propagam "de out. em diante" │
│ SyncEngine (actor) ── push/pull ────────┼───────►│ Auth: Entrar com Apple               │
│ LocalCache (SwiftData: linhas JSON +    │        │ Edge Functions (Deno):               │
│   fila de envio + cursores)             │        │   /pagamentos  /piloto (cron)        │
└─────────────────────────────────────────┘        │   /pluggy-connect-token              │
                                                   │ pg_cron: abre o mês todo dia 1       │
                                                   └──────────────────────────────────────┘
```

- **`Packages/LastroKit`**: domínio puro em Swift (sem UI), com modelos, `Money` em
  centavos, formatação BRL, o `Ledger` e as contas do mês (sobra prevista, saldo
  confirmado, pode gastar hoje, faturas, miudezas, histórico, planejamento),
  além da conversão OKLCH → Display P3. Os testes usam como oráculo os números
  tirados da lógica do protótipo.
- **`Lastro/`**: o app.
  - `DesignSystem/` guarda os tokens (cores OKLCH, tipografia com tracking em em),
    as superfícies (painel fosco e vidro) e os componentes.
  - `Data/` tem o `AppStore`, o cache SwiftData, o `SyncEngine` e o cliente Supabase.
  - `Features/` tem as telas.
- **`supabase/`**: migrations, testes de schema (rodam num Postgres puro) e edge functions.

### Sync offline-first

1. Toda escrita vale na hora. O `AppStore` muda o `Ledger`, o `LocalCache` grava a
   linha e ela entra na fila (`PendingChange`, só a última versão de cada registro).
2. **Push**: upsert idempotente por tabela, na ordem das chaves estrangeiras. Os ids
   são UUIDs gerados no aparelho, então reenviar não duplica.
3. **Pull**: por tabela, `updated_at > cursor − 5s` (a sobreposição cobre commits
   fora de ordem), paginado de 1000 em 1000. Apagar é soft delete (`deleted_at`),
   então exclusões também chegam.
4. Um registro com mudança pendente não é sobrescrito pelo pull. Em conflito, vence
   a última escrita, com o relógio do servidor (`updated_at` vem de trigger).

O cache guarda **o JSON de cada linha**, não um espelho tabela por tabela. Mudar o
schema do banco não exige migração do SwiftData.

### Regras que moram no servidor

- **Mês fechado é só leitura**: trigger em `transactions`, `month_budgets` e `month_extras`.
- **"Todo dia 1 o mês novo já nasce com ela"**: `open_month()` copia o orçamento do
  mês anterior e cria uma ocorrência de cada conta fixa. É idempotente (índice
  único `bill_id + month`) e roda pelo pg_cron, além de sempre que o app abre.
- **Conta variável** (luz, água, gás): o valor é estimado pela média dos 3 últimos
  meses confirmados.
- **"Alterações valem de outubro em diante"**: editar uma fixa atualiza só as
  ocorrências não confirmadas dos meses seguintes. Apagar tira as futuras.
- **Piloto** (`supabase/functions/_shared/policy.ts`, testado):
  - não paga se o saldo confirmado ficar abaixo da **trava**;
  - acima de **R$ 1.000**, fica `awaiting_approval` até o app aprovar com Face ID;
  - a trava é conferida de novo na aprovação;
  - nunca há dois pagamentos vivos para o mesmo lançamento (índice único parcial).
    O cron e o app podem pedir o mesmo pagamento ao mesmo tempo.
- `payments` só é escrita pelo servidor. O app lê.

### Pagamentos

`POST /pagamentos { tipo, valor, destino, data, exigeAprovacao, chave }`, como
previsto no protótipo, mais `POST /pagamentos/{id}/aprovar`. Os valores são em
centavos. O provedor fica atrás de `PaymentProvider`. A v1 usa o **sandbox**, que
não move dinheiro. Para ligar um provedor real (PSP ou API Pix de banco), basta
implementar `send()` e mudar `PAYMENT_PROVIDER`.

## Decisões

| Tema | Decisão |
| --- | --- |
| iOS mínimo | 26: Liquid Glass nativo (`glassEffect`, `GlassEffectContainer`), sem fallback. |
| Vidro | Só no que flutua: tab bar, botão +, botões do cabeçalho, card herói, alertas e sheets. Os cards de conteúdo são um fosco claro (material + branco 60%). |
| Cor | OKLCH do design convertido para **Display P3** em runtime. Cada categoria só guarda o matiz (`hue`), e ícone, fundo e barra derivam dele. |
| Ícones | SF Symbols no lugar dos SVGs do protótipo (mapeados em `categories.symbol`). |
| Tipografia | SF Pro do sistema, com tracking do CSS convertido (`-.035em` → `size × -0.035`). |
| Dinheiro | `Int` em centavos no app e `bigint` no banco. Nunca `Double` para guardar valor. |
| Projeto Xcode | XcodeGen (`project.yml`). O `.xcodeproj` não é versionado. |
| Login | Entrar com Apple → Supabase Auth (`signInWithIdToken`). |
| Dados iniciais | Seed do protótipo (`seed_demo()`, com as 18 fixas e 6 cartões). O importador de planilha fica para a fase 2. |

## Roadmap

**Fase 1 (esta entrega)**
- [x] Schema, RLS, regras e seed no Supabase, com testes
- [x] Edge functions `/pagamentos`, `/piloto` e `/pluggy-connect-token`, com a política testada
- [x] LastroKit com todas as contas do protótipo e testes batendo com ele
- [x] Design system (tokens, vidro, componentes)
- [x] Shell: tab bar de vidro + botão lançar, navegação, toast
- [x] **Hoje** completa: meses (fechado, corrente e planejamento), herói com 3 métricas, atalhos, para confirmar, piloto, miudezas e categorias
- [x] **Lançar gasto**: teclado, categoria, forma de pagamento, salvar
- [x] Autorização Face ID, ligada ao `/pagamentos`
- [x] Cache offline + fila + sync
- [x] Entrar com Apple e onboarding
- [x] CI (Postgres + Deno no Linux; LastroKit + app no macOS 26)

**Fase 2: o dia a dia**
- [x] Gastos (lista por dia, busca, filtros; toque confirma)
- [x] Detalhe de categoria (anel, padrão calculado dos dados, ticket médio)
- [x] Cartões (carrossel, fatura, limite, compras)
- [x] Histórico (barras de sobra, acumulado, maiores categorias)
- [x] Planejar (passo de R$ 50, itens só do mês)
- [x] Contas fixas: lista, criar, editar e apagar
- [x] Piloto (toggles, trava, status) · Dívidas · Metas · Mais · Ajustes (exportar CSV)
- [x] Recibos: confirmar e editar
- [ ] **Extensão de compartilhar** (App Group com o cache)
- [ ] **Escanear cupom** (VisionKit `DataScannerViewController` + extração do total)
- [ ] Importador de planilha (CSV/XLSX → fixas e categorias)

**Fase 3: piloto de verdade**
- [ ] Tela Piloto (toggles, trava, status vindos de `payments`)
- [ ] Push (APNs) para `awaiting_approval` e `blocked`
- [ ] Provedor de pagamento real atrás de `PaymentProvider`
- [ ] Linha digitável de boleto nas fixas
- [ ] Pluggy: conectar banco, webhooks, conciliação automática ("o mês bate com o banco")
- [ ] Dívidas, Metas e Ajustes (Face ID ao abrir, lembrete às 21h, widget, Siri)

## Rodando

Veja o [README](../README.md).
