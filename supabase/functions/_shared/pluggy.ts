// Sincroniza um item da Pluggy: conexão → contas → transações → conciliação.
// Usado pelo app (/pluggy) e pelos webhooks (/pluggy-webhook). Idempotente:
// transações são upsert por id da Pluggy, e cada transação do banco só vira
// (ou casa com) um lançamento uma vez.
import { type Account, PluggyClient, type Transaction } from "npm:pluggy-sdk@0.90";
import type { Db } from "./payments.ts";
import { monthOf } from "./policy.ts";
import { type Action, type BankTx, type CategoryRef, type LedgerEntry, reconcile } from "./reconcile.ts";

export function pluggyClient(): PluggyClient {
  const clientId = Deno.env.get("PLUGGY_CLIENT_ID");
  const clientSecret = Deno.env.get("PLUGGY_CLIENT_SECRET");
  if (!clientId || !clientSecret) throw new Error("PLUGGY_CLIENT_ID/PLUGGY_CLIENT_SECRET não configurados");
  return new PluggyClient({ clientId, clientSecret });
}

export interface SyncSummary {
  accounts: number;
  imported: number;
  matched: number;
  created: number;
  ignored: number;
}

export interface SyncFilter {
  /** Transações com data a partir de (YYYY-MM-DD). */
  dateFrom?: string;
  /** Transações criadas na Pluggy depois de (ISO). Webhook transactions/created. */
  createdAtFrom?: string;
  /** Só estas transações (webhook transactions/updated). */
  ids?: string[];
  /** Só esta conta. */
  accountId?: string;
}

export async function syncItem(db: Db, pluggy: PluggyClient, userId: string, itemId: string, filter: SyncFilter): Promise<SyncSummary> {
  const item = await pluggy.fetchItem(itemId);
  const { data: conn, error: e1 } = await db.from("bank_connections").upsert({
    user_id: userId,
    pluggy_item_id: itemId,
    connector_name: item.connector?.name ?? "Banco",
    connector_logo: item.connector?.imageUrl ?? null,
    status: item.status,
    error_message: item.error?.message ?? null,
    deleted_at: null,
  }, { onConflict: "pluggy_item_id" }).select("id").single();
  if (e1) throw e1;

  const accounts = (await pluggy.fetchAccounts(itemId)).results
    .filter((a) => !filter.accountId || a.id === filter.accountId);

  let imported = 0;
  for (const acc of accounts) {
    const cardId = acc.type === "CREDIT" ? await linkCard(db, userId, acc) : null;
    const { data: bankAccount, error: e2 } = await db.from("bank_accounts").upsert({
      user_id: userId,
      connection_id: conn.id,
      pluggy_account_id: acc.id,
      type: acc.type,
      subtype: acc.subtype,
      name: acc.marketingName ?? acc.name,
      number: acc.number,
      balance_cents: Math.round((acc.balance ?? 0) * 100),
      card_id: cardId,
      deleted_at: null,
    }, { onConflict: "pluggy_account_id" }).select("id").single();
    if (e2) throw e2;

    const txs = await pluggy.fetchAllTransactions(acc.id, filter.ids ? { ids: filter.ids }
      : filter.createdAtFrom ? { createdAtFrom: filter.createdAtFrom }
      : { dateFrom: filter.dateFrom });
    const rows = txs.map((t) => bankRow(userId, bankAccount.id, t));
    for (let i = 0; i < rows.length; i += 500) {
      const { error } = await db.from("bank_transactions").upsert(rows.slice(i, i + 500), { onConflict: "pluggy_transaction_id" });
      if (error) throw error;
    }
    imported += rows.length;
  }

  const result = await reconcileUser(db, userId);
  await db.from("bank_connections").update({ last_synced_at: new Date().toISOString() }).eq("id", conn.id);
  return { accounts: accounts.length, imported, ...result };
}

function bankRow(userId: string, bankAccountId: string, t: Transaction) {
  const date = t.date instanceof Date ? t.date.toISOString() : String(t.date);
  return {
    user_id: userId,
    bank_account_id: bankAccountId,
    pluggy_transaction_id: t.id,
    date: date.slice(0, 10),
    description: t.description ?? "",
    amount_cents: Math.round(Math.abs(t.amount) * 100),
    type: t.type,
    category: t.category,
    merchant: t.merchant?.businessName || t.merchant?.name || null,
    status: t.status ?? "POSTED",
    deleted_at: null,
  };
}

/** Conta de cartão da Pluggy ↔ cartão do Lastro (pelo final ou pelo nome); cria se não existir. */
async function linkCard(db: Db, userId: string, acc: Account): Promise<string> {
  const { data: existing } = await db.from("bank_accounts").select("card_id").eq("pluggy_account_id", acc.id).maybeSingle();
  if (existing?.card_id) return existing.card_id;

  const last4 = (acc.number ?? "").replace(/\D/g, "").slice(-4);
  const { data: cards } = await db.from("cards").select("id, name, subtitle").eq("user_id", userId).is("deleted_at", null);
  const name = (acc.marketingName ?? acc.name).toLowerCase();
  const found = (cards ?? []).find((c) =>
    (last4 && (c.subtitle ?? "").includes(last4)) || name.includes(c.name.toLowerCase()) || c.name.toLowerCase().includes(name)
  );
  if (found) return found.id;

  const day = (d: Date | string | null | undefined, fallback: number) =>
    d ? Math.min(31, Math.max(1, Number(new Date(d).toISOString().slice(8, 10)))) : fallback;
  const hues = [305, 48, 258, 350, 22, 150, 200, 90];
  const { data: created, error } = await db.from("cards").insert({
    user_id: userId,
    name: acc.marketingName ?? acc.name,
    subtitle: last4 ? `final ${last4}` : null,
    hue: hues[(cards?.length ?? 0) % hues.length],
    limit_cents: Math.round((acc.creditData?.creditLimit ?? 0) * 100),
    closing_day: day(acc.creditData?.balanceCloseDate, 1),
    due_day: day(acc.creditData?.balanceDueDate, 10),
    position: cards?.length ?? 0,
  }).select("id").single();
  if (error) throw error;
  return created.id;
}

/** Concilia tudo que está em aberto do usuário. */
export async function reconcileUser(db: Db, userId: string) {
  const { data: open, error } = await db.from("bank_transactions")
    .select("id, date, amount_cents, type, description, category, merchant, bank_accounts!inner(type, card_id)")
    .eq("user_id", userId).is("transaction_id", null).is("ignored_reason", null).is("deleted_at", null);
  if (error) throw error;
  if (!open?.length) return { matched: 0, created: 0, ignored: 0 };

  // deno-lint-ignore no-explicit-any
  const txs: BankTx[] = open.map((r: any) => ({
    id: r.id,
    date: r.date,
    amountCents: Number(r.amount_cents),
    type: r.type,
    description: r.description,
    category: r.category,
    merchant: r.merchant,
    isCreditAccount: r.bank_accounts.type === "CREDIT",
    cardId: r.bank_accounts.card_id,
  }));
  const months = [...new Set(txs.map((t) => t.date.slice(0, 8) + "01"))];

  const [{ data: entryRows }, { data: catRows }, { data: closedRows }] = await Promise.all([
    db.from("transactions")
      .select("id, month, day, description, amount_cents, confirmed, bill_id, estimated, bank_confirmed_at, category_id")
      .eq("user_id", userId).in("month", months).is("deleted_at", null),
    db.from("categories").select("id, slug, name, nature").eq("user_id", userId).is("deleted_at", null),
    db.from("months").select("month").eq("user_id", userId).eq("status", "closed").in("month", months),
  ]);

  // deno-lint-ignore no-explicit-any
  const entries: LedgerEntry[] = (entryRows ?? []).map((e: any) => ({
    id: e.id,
    month: e.month,
    day: e.day,
    description: e.description,
    amountCents: Number(e.amount_cents),
    confirmed: e.confirmed,
    billId: e.bill_id,
    estimated: e.estimated,
    bankConfirmed: e.bank_confirmed_at != null,
    categoryId: e.category_id,
  }));

  const actions = reconcile(txs, entries, (catRows ?? []) as CategoryRef[], new Set((closedRows ?? []).map((m) => m.month)));
  return await apply(db, userId, actions);
}

async function apply(db: Db, userId: string, actions: Action[]) {
  const now = new Date().toISOString();
  const count = { matched: 0, created: 0, ignored: 0 };
  for (const a of actions) {
    if (a.kind === "ignore") {
      await db.from("bank_transactions").update({ ignored_reason: a.reason }).eq("id", a.bankTxId);
      count.ignored++;
    } else if (a.kind === "link") {
      // Reserva a transação do banco antes: se outra execução chegou primeiro, não faz nada.
      const { data: claimed } = await db.from("bank_transactions").update({ transaction_id: a.entryId })
        .eq("id", a.bankTxId).is("transaction_id", null).select("id");
      if (!claimed?.length) continue;
      await db.from("transactions").update({
        confirmed: true,
        bank_confirmed_at: now,
        ...(a.amountCents != null ? { amount_cents: a.amountCents, estimated: false } : {}),
      }).eq("id", a.entryId);
      count.matched++;
    } else {
      const e = a.entry;
      const method = e.method === "cartao" && !e.cardId ? "debito" : e.method;
      const { data: created, error } = await db.from("transactions").insert({
        user_id: userId,
        month: e.month,
        day: e.day,
        description: e.description,
        category_id: e.categoryId,
        amount_cents: e.amountCents,
        method,
        card_id: method === "cartao" ? e.cardId : null,
        confirmed: true,
        kind: "variavel",
        source: "bank",
        bank_confirmed_at: now,
      }).select("id").single();
      if (error) {
        console.error("criar lançamento", error);
        continue;
      }
      const { data: claimed } = await db.from("bank_transactions").update({ transaction_id: created.id })
        .eq("id", a.bankTxId).is("transaction_id", null).select("id");
      if (!claimed?.length) {
        await db.from("transactions").delete().eq("id", created.id); // perdeu a corrida
        continue;
      }
      count.created++;
    }
  }
  return count;
}

/** Primeiro dia do mês corrente no fuso do usuário: a sincronização começa daqui ("começar limpo"). */
export async function currentMonthStart(db: Db, userId: string): Promise<string> {
  const { data } = await db.from("profiles").select("timezone").eq("user_id", userId).maybeSingle();
  return monthOf(new Date(), data?.timezone ?? "America/Sao_Paulo");
}
