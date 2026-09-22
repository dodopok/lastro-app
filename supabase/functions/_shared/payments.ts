// Fluxo de pagamento compartilhado por /pagamentos (app) e /piloto (cron).
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { decide, monthOf } from "./policy.ts";
import { type PaymentProvider, providerFromEnv } from "./provider.ts";

export type Db = SupabaseClient;

export function adminClient(): Db {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
}

export function provider(): PaymentProvider {
  return providerFromEnv((k) => Deno.env.get(k));
}

export interface NewPayment {
  userId: string;
  method: "pix" | "boleto";
  amountCents: number;
  destination: string;
  scheduledFor: string; // YYYY-MM-DD
  idempotencyKey: string;
  billId?: string | null;
  transactionId?: string | null;
  forceApproval?: boolean;
}

export interface PaymentRow {
  id: string;
  user_id: string;
  bill_id: string | null;
  transaction_id: string | null;
  amount_cents: number;
  method: "pix" | "boleto";
  destination: string;
  scheduled_for: string;
  status: string;
  requires_approval: boolean;
  idempotency_key: string;
  failure_reason: string | null;
}

async function limits(db: Db, userId: string, month: string) {
  const { data: profile, error } = await db.from("profiles")
    .select("safety_floor_cents, approval_threshold_cents, timezone")
    .eq("user_id", userId).single();
  if (error) throw error;
  const { data: balance, error: e2 } = await db.rpc("confirmed_balance_cents", { p_user: userId, p_month: month });
  if (e2) throw e2;
  return {
    floorCents: Number(profile.safety_floor_cents),
    approvalThresholdCents: Number(profile.approval_threshold_cents),
    balanceCents: Number(balance),
    timezone: profile.timezone as string,
  };
}

/** Cria o pagamento (idempotente pela chave) e já executa se a política deixar. */
export async function submit(db: Db, p: NewPayment): Promise<PaymentRow> {
  const existing = await db.from("payments").select("*").eq("idempotency_key", p.idempotencyKey).maybeSingle();
  if (existing.error) throw existing.error;
  if (existing.data) return existing.data as PaymentRow;

  // Nunca dois pagamentos vivos para o mesmo lançamento: o piloto (cron) e o
  // app podem pedir o mesmo com chaves diferentes.
  if (p.transactionId) {
    const live = await db.from("payments").select("*")
      .eq("transaction_id", p.transactionId)
      .in("status", ["scheduled", "awaiting_approval", "processing", "paid"])
      .maybeSingle();
    if (live.error) throw live.error;
    if (live.data) return live.data as PaymentRow;
  }

  const l = await limits(db, p.userId, monthOf(new Date(p.scheduledFor + "T12:00:00Z")));
  const d = decide({ amountCents: p.amountCents, ...l, forceApproval: p.forceApproval });

  const { data, error } = await db.from("payments").insert({
    user_id: p.userId,
    bill_id: p.billId ?? null,
    transaction_id: p.transactionId ?? null,
    amount_cents: p.amountCents,
    method: p.method,
    destination: p.destination,
    scheduled_for: p.scheduledFor,
    status: d.status === "processing" ? "scheduled" : d.status,
    requires_approval: d.status === "awaiting_approval",
    failure_reason: d.status === "processing" ? null : d.reason,
    idempotency_key: p.idempotencyKey,
  }).select("*").single();
  if (error) throw error;

  return d.status === "processing" ? await execute(db, data as PaymentRow) : data as PaymentRow;
}

/** Passo 2 do Face ID: o app autenticou localmente e chama aprovar. */
export async function approve(db: Db, userId: string, paymentId: string): Promise<PaymentRow> {
  const { data, error } = await db.from("payments").select("*")
    .eq("id", paymentId).eq("user_id", userId).single();
  if (error) throw error;
  const row = data as PaymentRow;
  if (row.status !== "awaiting_approval") return row;

  // A trava é conferida de novo: o saldo pode ter mudado desde o pedido.
  const l = await limits(db, userId, monthOf(new Date(row.scheduled_for + "T12:00:00Z")));
  const d = decide({ amountCents: row.amount_cents, ...l, approved: true });
  if (d.status === "blocked") {
    return await update(db, row.id, { status: "blocked", failure_reason: d.reason });
  }
  const approved = await update(db, row.id, { status: "scheduled", approved_at: new Date().toISOString() });
  return await execute(db, approved);
}

async function execute(db: Db, row: PaymentRow): Promise<PaymentRow> {
  const prov = provider();
  await update(db, row.id, { status: "processing", provider: prov.name });
  const r = await prov.send({
    id: row.id,
    method: row.method,
    amountCents: row.amount_cents,
    destination: row.destination,
    idempotencyKey: row.idempotency_key,
  });
  if (r.status === "failed") {
    return await update(db, row.id, { status: "failed", failure_reason: r.reason });
  }
  const done = await update(db, row.id, { status: r.status, provider_ref: r.providerRef });
  if (r.status === "paid" && row.transaction_id) {
    // Pago = confirmado. O app recebe isso no próximo sync.
    const { error } = await db.from("transactions").update({ confirmed: true }).eq("id", row.transaction_id);
    if (error) throw error;
  }
  return done;
}

async function update(db: Db, id: string, patch: Record<string, unknown>): Promise<PaymentRow> {
  const { data, error } = await db.from("payments").update(patch).eq("id", id).select("*").single();
  if (error) throw error;
  return data as PaymentRow;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
