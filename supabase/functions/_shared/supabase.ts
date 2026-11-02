import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

/**
 * A client that acts *as the caller*: it forwards the user's JWT so every
 * query is filtered by row-level security exactly as it would be from the app.
 * Returns null when the request carries no bearer token.
 */
export function clientForCaller(req: Request): SupabaseClient | null {
  const auth = req.headers.get("authorization");
  if (!auth || !auth.toLowerCase().startsWith("bearer ")) return null;
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** A privileged client for server-side work (webhooks, cleanup). Never used to answer a user query. */
export function serviceClient(): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
