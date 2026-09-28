import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export function obtenerClienteSupabase(req: Request) {
  const authHeader = req.headers.get("Authorization");
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader ?? "" } } }
  );
}

export function obtenerClienteAdmin() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );
}

/**
 * Exige que quien llama sea administrador nacional o moderador de algún departamento.
 * Devuelve null si está autorizado, o una Response 401/403 lista para retornar.
 */
export async function exigirModerador(req: Request, corsHeaders: Record<string, string>): Promise<Response | null> {
  const cliente = obtenerClienteSupabase(req);
  const { data: permisos, error } = await cliente.rpc("mis_permisos");
  const json = (status: number, error: string) => new Response(JSON.stringify({ error }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" }
  });
  if (error || !permisos?.autenticado) return json(401, "Debes iniciar sesión.");
  if (!permisos.es_admin_nacional && !(permisos.departamentos_moderacion?.length > 0)) {
    return json(403, "Solo administradores y moderadores pueden usar el estudio de IA.");
  }
  return null;
}
