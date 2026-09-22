# Lastro

Orçamento pessoal para iOS 26, com SwiftUI e Liquid Glass e Supabase por trás.
Seu mês inteiro, confirmado com o banco.

- **Plano, arquitetura e roadmap:** [`docs/PLANO.md`](docs/PLANO.md)
- **Design de referência:** [`docs/design/Lastro.dc.html`](docs/design/Lastro.dc.html) (abra no navegador)

```
Lastro/                 app SwiftUI (DesignSystem, Data, Features)
LastroTests/            testes do app
Packages/LastroKit/     domínio puro: dinheiro, meses, contas do mês, cores
supabase/               migrations, testes de schema, edge functions
project.yml             projeto Xcode (XcodeGen)
```

## App

Requer Xcode 26 e `brew install xcodegen`.

```sh
xcodegen generate
open Lastro.xcodeproj
```

O projeto tem dois alvos: o app (`Lastro`) e a extensão de compartilhar
(`LastroShare`). Os dois usam o App Group `group.app.lastro` para a caixa de
entrada de recibos. Num aparelho, ative App Groups para os dois bundle ids no
seu time (o simulador não exige).

Sem configurar nada, o app abre em **modo demo**: os dados do protótipo ficam em
memória, sem login e sem rede. Para usar o Supabase:

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# preencha SUPABASE_URL, SUPABASE_ANON_KEY e LASTRO_TEAM_ID
xcodegen generate
```

Testes do domínio (rodam em segundos, sem simulador):

```sh
swift test --package-path Packages/LastroKit
```

## Backend (Supabase)

```sh
supabase start                 # sobe local (Docker)
supabase db reset              # aplica as migrations
supabase functions serve       # edge functions locais
```

Os testes de schema rodam em qualquer Postgres 16, sem Docker e sem Supabase CLI:

```sh
supabase/tests/run.sh
```

Edge functions (Deno):

```sh
cd supabase/functions && deno test _shared/ && deno check */index.ts
```

Segredos das functions (`supabase secrets set …`). **Nunca** coloque isso no app nem no git:

| Variável | Para quê |
| --- | --- |
| `PAYMENT_PROVIDER` | `sandbox` (padrão; não move dinheiro) |
| `CRON_SECRET` | protege `/piloto`, chamado pelo cron |
| `PLUGGY_CLIENT_ID`, `PLUGGY_CLIENT_SECRET` | Open Finance (painel da Pluggy → Applications) |
| `PLUGGY_WEBHOOK_SECRET` | segredo na URL do webhook da Pluggy (gere um aleatório) |
| `PLUGGY_SANDBOX` | `true` mostra os bancos de teste da Pluggy no widget |

### Ligando a Pluggy

```sh
supabase link --project-ref SEU-PROJETO
supabase db push                                   # migrations (inclui bank_*)
supabase secrets set \
  PLUGGY_CLIENT_ID=... PLUGGY_CLIENT_SECRET=... \
  PLUGGY_WEBHOOK_SECRET=$(openssl rand -hex 24) PLUGGY_SANDBOX=true
supabase functions deploy pluggy pluggy-webhook
```

O webhook é registrado sozinho em cada conexão (vai no connect token), então não
precisa configurar nada no painel da Pluggy. No app: Ajustes → Bancos conectados →
Conectar banco. Com `PLUGGY_SANDBOX=true`, use o conector "Pluggy Bank" (usuário
`user-ok`, senha `password-ok`) para testar sem banco de verdade.

Para ligar o login com Apple no projeto Supabase, vá em Authentication → Providers →
Apple e use o bundle id `app.lastro.ios`.
