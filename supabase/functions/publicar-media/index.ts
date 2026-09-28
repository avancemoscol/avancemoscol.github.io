import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { obtenerClienteAdmin } from "../_shared/auth.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    const { record, old_record } = payload;

    // Solo procesar si cambió a estado aprobado
    if (record?.estado === "aprobado" && old_record?.estado !== "aprobado") {
      const supabaseAdmin = obtenerClienteAdmin();
      const publicacionId = record.id;
      const destinoBucket = record.visibilidad === "publica" ? "media-publica" : "media-miembros";

      // Obtener media de la publicación
      const { data: mediaItems } = await supabaseAdmin
        .from("publicacion_media")
        .select("*")
        .eq("publicacion_id", publicacionId);

      for (const item of (mediaItems || [])) {
        if (item.bucket === "media-pendiente") {
          const rutaNueva = `${record.departamento_id || 'nacional'}/${record.autor_id}/${item.path.split('/').pop()}`;

          // Copiar objeto
          const { error: copyErr } = await supabaseAdmin.storage
            .from("media-pendiente")
            .copy(item.path, rutaNueva, { destinationBucket: destinoBucket });

          if (!copyErr) {
            await supabaseAdmin
              .from("publicacion_media")
              .update({ bucket: destinoBucket, path: rutaNueva })
              .eq("id", item.id);
          }
        }
      }
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
});
