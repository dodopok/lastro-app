import { assertEquals } from "jsr:@std/assert@1";
import { type BankTx, type CategoryRef, categorize, type LedgerEntry, prettyDescription, reconcile } from "./reconcile.ts";

const cats: CategoryRef[] = [
  { id: "c-moradia", slug: "moradia", name: "Moradia", nature: "fixo" },
  { id: "c-mercado", slug: "mercado", name: "Mercado", nature: "variavel" },
  { id: "c-rango", slug: "rango", name: "Rango & Café", nature: "variavel" },
  { id: "c-transporte", slug: "transporte", name: "Transporte", nature: "variavel" },
  { id: "c-saude", slug: "saude", name: "Saúde", nature: "fixo" },
  { id: "c-imprevistos", slug: "imprevistos", name: "Imprevistos", nature: "reserva" },
];

const entry = (p: Partial<LedgerEntry> & { id: string; day: number; amountCents: number }): LedgerEntry => ({
  month: "2026-09-01", description: p.id, confirmed: true, billId: null, estimated: false, bankConfirmed: false,
  categoryId: "c-rango", ...p,
});

const tx = (p: Partial<BankTx> & { id: string; date: string; amountCents: number }): BankTx => ({
  type: "DEBIT", description: p.id, isCreditAccount: false, ...p,
});

const entries: LedgerEntry[] = [
  entry({ id: "aluguel", description: "Aluguel", day: 5, amountCents: 320000, billId: "b1", categoryId: "c-moradia" }),
  entry({ id: "luz", description: "Luz", day: 10, amountCents: 41250, billId: "b2", estimated: true, confirmed: false, categoryId: "c-moradia" }),
  entry({ id: "ifood-21", description: "iFood", day: 21, amountCents: 3650 }),
  entry({ id: "uber-19", description: "Uber", day: 19, amountCents: 1890, categoryId: "c-transporte" }),
  entry({ id: "cafe-6", description: "Café", day: 6, amountCents: 1200 }),
  entry({ id: "ja-conferido", description: "Padaria", day: 5, amountCents: 1450, bankConfirmed: true }),
];

Deno.test("conta fixa com o mesmo valor confirma", () => {
  const [a] = reconcile([tx({ id: "t1", date: "2026-09-05", amountCents: 320000, description: "PIX ENVIADO IMOBILIARIA SOL" })], entries, cats, new Set());
  assertEquals(a, { kind: "link", bankTxId: "t1", entryId: "aluguel" });
});

Deno.test("conta variável: valor real substitui o estimado (ENEL × Luz)", () => {
  const [a] = reconcile([tx({ id: "t2", date: "2026-09-11", amountCents: 43890, description: "ENEL DISTRIBUICAO RJ" })], entries, cats, new Set());
  assertEquals(a, { kind: "link", bankTxId: "t2", entryId: "luz", amountCents: 43890 });
});

Deno.test("não duplica o que já foi lançado à mão", () => {
  const [a] = reconcile([tx({ id: "t3", date: "2026-09-22", amountCents: 3650, description: "IFOOD *IFOOD", isCreditAccount: true, cardId: "nubank" })], entries, cats, new Set());
  assertEquals(a, { kind: "link", bankTxId: "t3", entryId: "ifood-21" });
});

Deno.test("gasto novo vira lançamento categorizado, no cartão", () => {
  const [a] = reconcile([tx({ id: "t4", date: "2026-09-22", amountCents: 2550, description: "UBER *TRIP HELP.UBER.COM", isCreditAccount: true, cardId: "uniclass" })], entries, cats, new Set());
  assertEquals(a, {
    kind: "create", bankTxId: "t4",
    entry: { month: "2026-09-01", day: 22, description: "Uber Trip Help.uber.com", categoryId: "c-transporte", amountCents: 2550, method: "cartao", cardId: "uniclass" },
  });
});

Deno.test("dois débitos iguais: só um casa, o outro vira lançamento", () => {
  const actions = reconcile([
    tx({ id: "a", date: "2026-09-06", amountCents: 1200, description: "CAFE DO PONTO" }),
    tx({ id: "b", date: "2026-09-07", amountCents: 1200, description: "CAFE DO PONTO" }),
  ], entries, cats, new Set());
  assertEquals(actions.filter((x) => x.kind === "link").length, 1);
  assertEquals(actions.filter((x) => x.kind === "create").length, 1);
});

Deno.test("longe demais no tempo não casa", () => {
  const [a] = reconcile([tx({ id: "t5", date: "2026-09-15", amountCents: 1890, description: "UBER" })], entries, cats, new Set());
  assertEquals(a.kind, "create");
});

Deno.test("já conferido pelo banco não casa de novo", () => {
  const [a] = reconcile([tx({ id: "t6", date: "2026-09-05", amountCents: 1450, description: "PADARIA" })], entries, cats, new Set());
  assertEquals(a.kind, "create");
});

Deno.test("ignora entrada, pagamento de fatura, transferência própria e mês fechado", () => {
  const actions = reconcile([
    tx({ id: "salario", date: "2026-09-05", amountCents: -1500000, type: "CREDIT", description: "SALARIO" }),
    tx({ id: "fatura", date: "2026-09-05", amountCents: 246350, description: "PAGAMENTO DE FATURA NUBANK" }),
    tx({ id: "invest", date: "2026-09-05", amountCents: 100000, description: "APLICACAO CDB", category: "Investments" }),
    tx({ id: "agosto", date: "2026-08-20", amountCents: 5000, description: "PADARIA" }),
  ], entries, cats, new Set(["2026-08-01"]));
  const reasons = Object.fromEntries(actions.map((a) => [a.bankTxId, a.kind === "ignore" ? a.reason : a.kind]));
  assertEquals(reasons, { salario: "entrada", fatura: "pagamento de fatura", invest: "transferência própria", agosto: "mês fechado" });
});

Deno.test("categorias por marca, categoria da Pluggy e palavra inteira", () => {
  const cat = (description: string, category?: string) =>
    categorize({ id: "x", date: "2026-09-01", amountCents: 1, type: "DEBIT", description, category, isCreditAccount: false }, cats)?.slug;
  assertEquals(cat("DROGASIL 123"), "saude");
  assertEquals(cat("COMPRA 4821", "Groceries"), "mercado");
  assertEquals(cat("PARENT CLUB"), "imprevistos"); // "rent" não casa dentro de "parent"
  assertEquals(cat("UBER EATS"), "rango");
  assertEquals(cat("99APP *CORRIDA"), "transporte");
});

Deno.test("descrição limpa", () => {
  assertEquals(prettyDescription("COMPRA CARTAO - PADARIA REAL 12/09"), "Padaria Real");
  assertEquals(prettyDescription("PIX ENVIADO JOAO DA SILVA"), "Joao da Silva");
});
