// Conciliação: transações do banco (Pluggy) × lançamentos do Lastro.
// Pura e testada (reconcile_test.ts). Quem executa as ações é _shared/pluggy.ts.
//
// Regras, em ordem:
//  1. Entradas (CREDIT), pagamento de fatura e transferência entre contas
//     próprias são ignorados: contariam o mesmo gasto duas vezes.
//  2. Mês fechado é só leitura: ignora.
//  3. Casa com um lançamento ainda não conferido pelo banco:
//     - conta fixa: mesmo valor e até 7 dias de diferença; conta variável
//       (estimada): até 35% de diferença se o nome parecer, e o valor real
//       substitui o estimado;
//     - qualquer outro: mesmo valor e até 3 dias (evita duplicar o que você
//       lançou à mão).
//  4. Senão, cria um lançamento novo, já categorizado.

export interface BankTx {
  id: string;
  date: string; // YYYY-MM-DD
  amountCents: number; // positivo = saiu
  type: "DEBIT" | "CREDIT";
  description: string;
  category?: string | null;
  merchant?: string | null;
  cardId?: string | null; // conta CREDIT ligada a um cartão
  isCreditAccount: boolean;
}

export interface LedgerEntry {
  id: string;
  month: string; // YYYY-MM-01
  day: number;
  description: string;
  amountCents: number;
  confirmed: boolean;
  billId: string | null;
  estimated: boolean;
  bankConfirmed: boolean;
  categoryId: string;
}

export interface CategoryRef {
  id: string;
  slug: string;
  name: string;
  nature: "fixo" | "variavel" | "parcelado" | "reserva";
}

export type Action =
  | { kind: "link"; bankTxId: string; entryId: string; amountCents?: number }
  | {
    kind: "create";
    bankTxId: string;
    entry: {
      month: string;
      day: number;
      description: string;
      categoryId: string;
      amountCents: number;
      method: "pix" | "debito" | "cartao";
      cardId: string | null;
    };
  }
  | { kind: "ignore"; bankTxId: string; reason: string };

export function reconcile(
  txs: BankTx[],
  entries: LedgerEntry[],
  categories: CategoryRef[],
  closedMonths: Set<string>,
): Action[] {
  const available = entries.filter((e) => !e.bankConfirmed);
  const used = new Set<string>();
  const actions: Action[] = [];

  // Os maiores primeiro: contas fixas grandes casam antes de gastos pequenos com o mesmo valor.
  for (const tx of [...txs].sort((a, b) => b.amountCents - a.amountCents)) {
    const skip = ignoreReason(tx);
    if (skip) {
      actions.push({ kind: "ignore", bankTxId: tx.id, reason: skip });
      continue;
    }
    const month = tx.date.slice(0, 8) + "01";
    if (closedMonths.has(month)) {
      actions.push({ kind: "ignore", bankTxId: tx.id, reason: "mês fechado" });
      continue;
    }

    const match = bestMatch(tx, available.filter((e) => !used.has(e.id)), categorize(tx, categories)?.id);
    if (match) {
      used.add(match.entry.id);
      actions.push({
        kind: "link",
        bankTxId: tx.id,
        entryId: match.entry.id,
        ...(match.entry.amountCents !== tx.amountCents ? { amountCents: tx.amountCents } : {}),
      });
      continue;
    }

    const category = categorize(tx, categories);
    if (!category) {
      actions.push({ kind: "ignore", bankTxId: tx.id, reason: "sem categoria" });
      continue;
    }
    actions.push({
      kind: "create",
      bankTxId: tx.id,
      entry: {
        month,
        day: Number(tx.date.slice(8, 10)),
        description: prettyDescription(tx.merchant || tx.description),
        categoryId: category.id,
        amountCents: tx.amountCents,
        method: tx.isCreditAccount ? "cartao" : /\bpix\b/i.test(tx.description) ? "pix" : "debito",
        cardId: tx.isCreditAccount ? tx.cardId ?? null : null,
      },
    });
  }
  return actions;
}

// ─────────────────────────────────────────────────────────── regras

export function ignoreReason(tx: BankTx): string | null {
  if (tx.type !== "DEBIT" || tx.amountCents <= 0) return "entrada";
  const text = normalize(`${tx.description} ${tx.category ?? ""}`);
  if (/pagamento (de )?fatura|pgto fatura|pag fatura|credit card payment|pagamento cartao/.test(text)) {
    return "pagamento de fatura";
  }
  if (/same person transfer|mesma titularidade|transferencia entre contas|aplicacao|investment/.test(text)) {
    return "transferência própria";
  }
  return null;
}

function bestMatch(tx: BankTx, candidates: LedgerEntry[], guessedCategoryId?: string) {
  let best: { entry: LedgerEntry; score: number } | null = null;
  for (const e of candidates) {
    const days = Math.abs(dayDiff(tx.date, e.month, e.day));
    const same = e.amountCents === tx.amountCents;
    const similar = nameSimilarity(tx.merchant || tx.description, e.description);
    let ok = false;
    if (e.billId) {
      const drift = Math.abs(e.amountCents - tx.amountCents) / Math.max(1, e.amountCents);
      // Conta estimada (luz, água): o nome raramente bate ("ENEL" × "Luz"); a categoria detectada serve de sinal.
      const looksLike = similar > 0 || guessedCategoryId === e.categoryId;
      ok = days <= 7 && (same || (e.estimated && drift <= 0.35 && looksLike));
    } else {
      ok = same && days <= 3;
    }
    if (!ok) continue;
    // Mais pontos: valor exato, mesmo nome, data mais perto, conta fixa pendente.
    const score = (same ? 100 : 0) + similar * 50 - days * 5 + (e.billId && !e.confirmed ? 10 : 0);
    if (!best || score > best.score) best = { entry: e, score };
  }
  return best;
}

function dayDiff(date: string, month: string, day: number): number {
  const a = Date.UTC(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10)));
  const b = Date.UTC(Number(month.slice(0, 4)), Number(month.slice(5, 7)) - 1, day);
  return Math.round((a - b) / 86_400_000);
}

/** 0…1: proporção de palavras (≥3 letras) do lançamento que aparecem no texto do banco. */
export function nameSimilarity(bank: string, entry: string): number {
  const words = normalize(entry).split(/[^a-z0-9]+/).filter((w) => w.length >= 3);
  if (words.length === 0) return 0;
  const hay = normalize(bank);
  return words.filter((w) => hay.includes(w)).length / words.length;
}

// ─────────────────────────────────────────────────────────── categorias

// Marca/loja no texto do banco → categoria (mesmas do ReceiptParser do app).
const KEYWORDS: [string, string[]][] = [
  ["rango", ["ifood", "rappi", "uber eats", "padaria", "panificadora", "cafe", "cafeteria", "restaurante", "lanchonete",
    "pizzaria", "burger", "mcdonalds", "bk", "starbucks", "eating out", "restaurants", "food delivery", "bares e restaurantes"]],
  ["mercado", ["supermercado", "mercado", "mercadinho", "atacadao", "assai", "carrefour", "pao de acucar", "hortifruti",
    "groceries", "supermarkets"]],
  ["transporte", ["uber", "99app", "99 pop", "cabify", "posto", "shell", "ipiranga", "combustivel", "estacionamento",
    "sem parar", "conectcar", "veloe", "pedagio", "metro", "transportation", "taxi", "gas station", "gas stations",
    "parking", "public transport", "tolls"]],
  ["saude", ["drogasil", "droga raia", "drogaria", "farmacia", "pague menos", "laboratorio", "clinica", "hospital",
    "pharmacy", "health", "dentist", "gym", "academia", "smartfit", "smart fit"]],
  ["moradia", ["enel", "light", "cemig", "copel", "sabesp", "cedae", "comgas", "condominio", "aluguel", "vivo", "claro",
    "tim", "oi fibra", "net", "housing", "rent", "electricity", "water", "utilities", "internet", "telecom"]],
  ["lazer", ["netflix", "spotify", "disney", "hbo", "max com", "prime video", "youtube", "apple com", "cinema",
    "ingresso", "steam", "playstation", "leisure", "entertainment", "streaming", "digital services", "tickets", "games"]],
  ["igreja", ["igreja", "dizimo", "oferta", "donation", "donations", "doacao"]],
];

/** Texto em palavras separadas por um espaço, com espaço nas pontas: casa palavra inteira. */
function words(s: string): string {
  return " " + normalize(s).replace(/[^a-z0-9]+/g, " ").trim() + " ";
}

export function categorize(tx: BankTx, categories: CategoryRef[]): CategoryRef | null {
  const text = words(`${tx.merchant ?? ""} ${tx.description} ${tx.category ?? ""}`);
  const has = (k: string) => text.includes(words(k));
  const bySlug = (slug: string) => categories.find((c) => c.slug === slug);
  for (const [slug, keys] of KEYWORDS) {
    if (keys.some(has)) {
      const c = bySlug(slug);
      if (c) return c;
    }
  }
  // Nome de categoria do próprio usuário no texto (planilha importada com nomes próprios).
  const own = categories.find((c) => c.name.length >= 4 && has(c.name));
  if (own) return own;
  return bySlug("imprevistos") ?? categories.find((c) => c.nature === "reserva") ??
    categories.find((c) => c.nature === "variavel") ?? categories[0] ?? null;
}

/** "COMPRA CARTAO - UBER *TRIP HELP.UBER.CO" → "Uber Trip Help.uber.co" */
export function prettyDescription(s: string): string {
  const cleaned = s
    .replace(/^(compra( no)? (cartao|debito|credito)|pix (enviado|transf\w*)|pagamento|pgto|deb(ito)? aut\w*)\s*[-:]?\s*/i, "")
    .replace(/[*_]+/g, " ")
    .replace(/\s+\d{2}\/\d{2}(\/\d{2,4})?\b/g, "")
    .replace(/\s{2,}/g, " ")
    .trim();
  const base = cleaned || s.trim();
  return base.toLowerCase().split(" ").map((w, i) =>
    i > 0 && ["de", "da", "do", "das", "dos", "e"].includes(w) ? w : w.charAt(0).toUpperCase() + w.slice(1)
  ).join(" ").slice(0, 80);
}

export function normalize(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}
