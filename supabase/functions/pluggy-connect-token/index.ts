// "Conectar banco · em breve · Pluggy". Gera o connect token que o app passa
// para o Pluggy Connect. Credenciais ficam só aqui (PLUGGY_CLIENT_ID/SECRET).
import { json } from "../_shared/payments.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ erro: "use POST" }, 405);

  const clientId = Deno.env.get("PLUGGY_CLIENT_ID");
  const clientSecret = Deno.env.get("PLUGGY_CLIENT_SECRET");
  if (!clientId || !clientSecret) {
    return json({ erro: "Pluggy ainda não configurado" }, 501);
  }

  const auth = await fetch("https://api.pluggy.ai/auth", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ clientId, clientSecret }),
  });
  if (!auth.ok) return json({ erro: "falha ao autenticar na Pluggy" }, 502);
  const { apiKey } = await auth.json();

  const token = await fetch("https://api.pluggy.ai/connect_token", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": apiKey },
    body: JSON.stringify({}),
  });
  if (!token.ok) return json({ erro: "falha ao gerar connect token" }, 502);
  const { accessToken } = await token.json();
  return json({ connectToken: accessToken });
});
