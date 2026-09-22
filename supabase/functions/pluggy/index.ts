// Open Finance (Pluggy), chamado pelo app com o JWT do usuário.
//
// POST   /pluggy/token             { itemId? }  → { connectToken, sandbox }   (itemId = reconectar)
// POST   /pluggy/items             { itemId }   → resumo da 1ª sincronização (depois do widget)
// POST   /pluggy/sync                           → pede atualização ao banco e sincroniza o mês
// DELETE /pluggy/items/{connectionId}           → desconecta (apaga o item na Pluggy)
import { userFrom } from "../_shared/auth.ts";
import { adminClient, json } from "../_shared/payments.ts";
import { currentMonthStart, pluggyClient, syncItem } from "../_shared/pluggy.ts";

Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ erro: "não autenticado" }, 401);

  const path = new URL(req.url).pathname.split("/").filter(Boolean); // ["pluggy", ...]
  const route = `${req.method} ${path.slice(1).join("/")}`;
  const db = adminClient();

  try {
    const pluggy = pluggyClient();

    if (route === "POST token") {
      const body = await req.json().catch(() => ({}));
      const secret = Deno.env.get("PLUGGY_WEBHOOK_SECRET");
      const webhookUrl = secret
        ? `${Deno.env.get("SUPABASE_URL")}/functions/v1/pluggy-webhook?secret=${encodeURIComponent(secret)}`
        : undefined;
      const { accessToken } = await pluggy.createConnectToken(body.itemId || undefined, {
        clientUserId: user,
        webhookUrl,
        avoidDuplicates: true,
      });
      return json({ connectToken: accessToken, sandbox: Deno.env.get("PLUGGY_SANDBOX") === "true" });
    }

    if (route === "POST items") {
      const { itemId } = await req.json();
      if (typeof itemId !== "string") return json({ erro: "itemId obrigatório" }, 422);
      // O connect token amarra o item ao usuário: não aceita item de outra pessoa.
      const item = await pluggy.fetchItem(itemId);
      if (item.clientUserId !== user) return json({ erro: "item não pertence a este usuário" }, 403);
      const summary = await syncItem(db, pluggy, user, itemId, { dateFrom: await currentMonthStart(db, user) });
      return json(summary, 201);
    }

    if (route === "POST sync") {
      const { data: conns, error } = await db.from("bank_connections").select("pluggy_item_id")
        .eq("user_id", user).is("deleted_at", null);
      if (error) throw error;
      const dateFrom = await currentMonthStart(db, user);
      const total = { accounts: 0, imported: 0, matched: 0, created: 0, ignored: 0 };
      for (const c of conns ?? []) {
        // Pede dados novos ao banco (chegam depois por webhook) e já concilia o que a Pluggy tem.
        await pluggy.updateItem(c.pluggy_item_id).catch((e) => console.warn("updateItem", e));
        const s = await syncItem(db, pluggy, user, c.pluggy_item_id, { dateFrom });
        for (const k of Object.keys(total) as (keyof typeof total)[]) total[k] += s[k];
      }
      return json(total);
    }

    if (req.method === "DELETE" && path[1] === "items" && path[2]) {
      const { data: conn, error } = await db.from("bank_connections").select("id, pluggy_item_id")
        .eq("id", path[2]).eq("user_id", user).maybeSingle();
      if (error) throw error;
      if (!conn) return json({ erro: "conexão não encontrada" }, 404);
      await pluggy.deleteItem(conn.pluggy_item_id).catch((e) => console.warn("deleteItem", e));
      const now = new Date().toISOString();
      await db.from("bank_accounts").update({ deleted_at: now }).eq("connection_id", conn.id);
      await db.from("bank_connections").update({ deleted_at: now, status: "DELETED" }).eq("id", conn.id);
      return json({ ok: true });
    }

    return json({ erro: "rota não encontrada" }, 404);
  } catch (e) {
    console.error(route, e);
    const message = e instanceof Error ? e.message : String(e);
    return json({ erro: message.includes("não configurados") ? "Pluggy ainda não configurada no servidor" : "falha na Pluggy" }, 500);
  }
});
