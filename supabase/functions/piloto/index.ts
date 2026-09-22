// Piloto automático: roda uma vez por dia (cron → POST com x-cron-secret).
// Para cada conta fixa com "pagar sozinho" que vence hoje (ou já venceu e
// ficou para trás), cria o pagamento. Idempotente por conta + mês.
//
// Agendar no Supabase (SQL):
//   select cron.schedule('lastro-piloto', '0 11 * * *', $$
//     select net.http_post(
//       url := '<SUPABASE_URL>/functions/v1/piloto',
//       headers := jsonb_build_object('x-cron-secret', '<CRON_SECRET>'))$$);
import { adminClient, json, submit } from "../_shared/payments.ts";
import { dayOf, monthOf } from "../_shared/policy.ts";

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return json({ erro: "proibido" }, 403);
  }

  const db = adminClient();
  const now = new Date();
  const { data: profiles, error } = await db.from("profiles").select("user_id, timezone");
  if (error) return json({ erro: error.message }, 500);

  const report: Record<string, number> = {};
  for (const p of profiles ?? []) {
    const month = monthOf(now, p.timezone);
    const today = dayOf(now, p.timezone);

    const { data: due, error: e2 } = await db.from("transactions")
      .select("id, day, amount_cents, bill_id, bills!inner(id, autopay, method, pix_key, deleted_at)")
      .eq("user_id", p.user_id).eq("month", month).eq("confirmed", false)
      .is("deleted_at", null).lte("day", today)
      .eq("bills.autopay", true).is("bills.deleted_at", null);
    if (e2) return json({ erro: e2.message }, 500);

    for (const t of due ?? []) {
      // deno-lint-ignore no-explicit-any
      const bill = (t as any).bills;
      if (bill.method === "debito") continue; // débito automático: o banco já cobra
      const destination = bill.method === "pix" ? bill.pix_key : null;
      if (!destination) continue; // boleto sem linha digitável: fica manual por enquanto

      const row = await submit(db, {
        userId: p.user_id,
        method: bill.method,
        amountCents: t.amount_cents,
        destination,
        scheduledFor: `${month.slice(0, 8)}${String(t.day).padStart(2, "0")}`,
        idempotencyKey: `bill:${t.bill_id}:${month}`,
        billId: t.bill_id,
        transactionId: t.id,
      });
      report[row.status] = (report[row.status] ?? 0) + 1;
    }
  }
  // TODO(push): avisar no aparelho os 'awaiting_approval' e 'blocked' (APNs).
  return json({ ok: true, ...report });
});
