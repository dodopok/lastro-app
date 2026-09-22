// Webhooks da Pluggy. A URL leva ?secret=PLUGGY_WEBHOOK_SECRET (definida no connect
// token), porque a Pluggy não assina o corpo. Responde na hora e processa em
// segundo plano (a Pluggy espera resposta rápida e reenvia em caso de erro).
import { adminClient, type Db, json } from "../_shared/payments.ts";
import { currentMonthStart, pluggyClient, reconcileUser, syncItem } from "../_shared/pluggy.ts";

// deno-lint-ignore no-explicit-any
type Payload = Record<string, any> & { event: string; eventId?: string; itemId?: string };

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

Deno.serve(async (req) => {
  const secret = Deno.env.get("PLUGGY_WEBHOOK_SECRET");
  if (!secret || new URL(req.url).searchParams.get("secret") !== secret) return json({ erro: "proibido" }, 403);
  if (req.method !== "POST") return json({ erro: "use POST" }, 405);

  const payload = await req.json().catch(() => null) as Payload | null;
  if (!payload?.event) return json({ erro: "evento inválido" }, 400);

  const work = handle(payload).catch((e) => console.error("webhook", payload.event, payload.eventId, e));
  if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(work);
  else await work;
  return json({ ok: true });
});

async function handle(p: Payload) {
  const db = adminClient();
  const pluggy = pluggyClient();
  if (!p.itemId) return;

  const userId = await ownerOf(db, pluggy, p.itemId);
  if (!userId) return; // item de ninguém conhecido: ignora

  switch (p.event) {
    case "item/created":
    case "item/updated":
    case "item/login_succeeded":
      await syncItem(db, pluggy, userId, p.itemId, { dateFrom: await currentMonthStart(db, userId) });
      break;

    case "item/error":
    case "item/waiting_user_input":
    case "item/waiting_user_action": {
      const item = await pluggy.fetchItem(p.itemId);
      await db.from("bank_connections").update({ status: item.status, error_message: item.error?.message ?? p.error?.message ?? null })
        .eq("pluggy_item_id", p.itemId);
      break;
    }

    case "item/deleted":
      await db.from("bank_connections").update({ deleted_at: new Date().toISOString(), status: "DELETED" })
        .eq("pluggy_item_id", p.itemId);
      break;

    case "transactions/created":
      await syncItem(db, pluggy, userId, p.itemId, { accountId: p.accountId, createdAtFrom: p.transactionsCreatedAtFrom });
      break;

    case "transactions/updated":
      await syncItem(db, pluggy, userId, p.itemId, { accountId: p.accountId, ids: p.transactionIds ?? [] });
      break;

    case "transactions/deleted": {
      // Some do banco: se o lançamento nasceu do banco, sai junto; se foi casado com um seu, só perde o selo.
      const ids: string[] = p.transactionIds ?? [];
      const { data: rows } = await db.from("bank_transactions").select("id, transaction_id")
        .in("pluggy_transaction_id", ids);
      const now = new Date().toISOString();
      for (const r of rows ?? []) {
        await db.from("bank_transactions").update({ deleted_at: now, transaction_id: null }).eq("id", r.id);
        if (!r.transaction_id) continue;
        const { data: e } = await db.from("transactions").select("source").eq("id", r.transaction_id).maybeSingle();
        if (e?.source === "bank") {
          await db.from("transactions").update({ deleted_at: now }).eq("id", r.transaction_id);
        } else {
          await db.from("transactions").update({ bank_confirmed_at: null }).eq("id", r.transaction_id);
        }
      }
      await reconcileUser(db, userId);
      break;
    }
  }
}

/** Dono do item: pela conexão já registrada ou pelo clientUserId do connect token. */
async function ownerOf(db: Db, pluggy: ReturnType<typeof pluggyClient>, itemId: string): Promise<string | null> {
  const { data } = await db.from("bank_connections").select("user_id").eq("pluggy_item_id", itemId).maybeSingle();
  if (data?.user_id) return data.user_id;
  const item = await pluggy.fetchItem(itemId).catch(() => null);
  if (!item?.clientUserId) return null;
  const { data: profile } = await db.from("profiles").select("user_id").eq("user_id", item.clientUserId).maybeSingle();
  return profile?.user_id ?? null;
}
