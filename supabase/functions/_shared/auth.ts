import { createClient } from "npm:@supabase/supabase-js@2";

/** Id do usuário a partir do JWT do app (Authorization: Bearer …). */
export async function userFrom(req: Request): Promise<string | null> {
  const auth = req.headers.get("authorization");
  if (!auth) return null;
  const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { authorization: auth } },
    auth: { persistSession: false },
  });
  const { data } = await client.auth.getUser();
  return data.user?.id ?? null;
}
