// POST /pagamentos                 { tipo, valor, destino, data, exigeAprovacao, contaId?, lancamentoId?, chave }
// POST /pagamentos/{id}/aprovar    depois do Face ID no aparelho
//
// valor em centavos. chave = chave de idempotência gerada pelo app (UUID).
import { userFrom } from "../_shared/auth.ts";
import { adminClient, approve, json, submit } from "../_shared/payments.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ erro: "use POST" }, 405);

  const user = await userFrom(req);
  if (!user) return json({ erro: "não autenticado" }, 401);

  const db = adminClient();
  const path = new URL(req.url).pathname.split("/").filter(Boolean); // ["pagamentos", id?, "aprovar"?]

  try {
    if (path.length === 3 && path[2] === "aprovar") {
      return json(await approve(db, user, path[1]));
    }
    if (path.length !== 1) return json({ erro: "rota não encontrada" }, 404);

    const b = await req.json();
    if (b.tipo !== "pix" && b.tipo !== "boleto") return json({ erro: "tipo deve ser pix ou boleto" }, 422);
    if (!Number.isInteger(b.valor) || b.valor <= 0) return json({ erro: "valor em centavos, inteiro > 0" }, 422);
    if (typeof b.destino !== "string" || !b.destino.trim()) return json({ erro: "destino obrigatório" }, 422);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(b.data ?? "")) return json({ erro: "data no formato AAAA-MM-DD" }, 422);
    if (typeof b.chave !== "string" || b.chave.length < 8) return json({ erro: "chave de idempotência obrigatória" }, 422);

    const row = await submit(db, {
      userId: user,
      method: b.tipo,
      amountCents: b.valor,
      destination: b.destino.trim(),
      scheduledFor: b.data,
      idempotencyKey: `app:${user}:${b.chave}`,
      billId: b.contaId ?? null,
      transactionId: b.lancamentoId ?? null,
      forceApproval: !!b.exigeAprovacao,
    });
    return json(row, 201);
  } catch (e) {
    console.error(e);
    return json({ erro: "falha ao processar pagamento" }, 500);
  }
});
