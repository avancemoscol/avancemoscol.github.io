import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { tokenGoogle, urlModelo } from "../_shared/vertex.ts";
import { obtenerClienteAdmin } from "../_shared/auth.ts";

const ESTILO_MARCA = "warm natural light, subtle teal and amber tones, editorial documentary photography, dignified and optimistic, realistic, no text, no logos";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { accion, descripcion, formato = "1:1", estilo = "editorial" } = await req.json();

    if (!descripcion) {
      return new Response(JSON.stringify({ error: "Falta la descripción para generar la imagen." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    const token = await tokenGoogle();
    const modelo = Deno.env.get("VERTEX_MODEL_IMAGE") || "gemini-2.5-flash-image";
    const endpoint = urlModelo("us-central1", modelo, "generateContent");

    const promptFinal = `${descripcion}. Style: ${ESTILO_MARCA}.`;

    const resVertex = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [{ text: promptFinal }]
          }
        ]
      })
    });

    if (!resVertex.ok) {
      const errTxt = await resVertex.text();
      throw new Error(`Vertex AI error ${resVertex.status}: ${errTxt}`);
    }

    const json = await resVertex.json();
    let imagenBytesBase64 = null;
    let mimeType = "image/png";

    const parts = json.candidates?.[0]?.content?.parts || [];
    for (const part of parts) {
      if (part.inlineData) {
        imagenBytesBase64 = part.inlineData.data;
        mimeType = part.inlineData.mimeType || "image/png";
        break;
      }
    }

    if (!imagenBytesBase64) {
      throw new Error("El modelo no devolvió una imagen en la respuesta.");
    }

    // Subir imagen decodificada a Supabase Storage (bucket ia-media)
    const supabaseAdmin = obtenerClienteAdmin();
    const rawBinary = Uint8Array.from(atob(imagenBytesBase64), (c) => c.charCodeAt(0));
    const archivoNombre = `${Date.now()}_${crypto.randomUUID()}.png`;

    const { data: uploadData, error: uploadErr } = await supabaseAdmin.storage
      .from("ia-media")
      .upload(archivoNombre, rawBinary, {
        contentType: mimeType,
        upsert: true
      });

    if (uploadErr) throw uploadErr;

    const { data: { publicUrl } } = supabaseAdmin.storage
      .from("ia-media")
      .getPublicUrl(archivoNombre);

    // Registrar en tabla media
    await supabaseAdmin.from("media").insert({
      bucket: "ia-media",
      path: archivoNombre,
      tipo: "imagen",
      mime: mimeType,
      origen: "ia_imagen",
      prompt: descripcion,
      prompt_final: promptFinal,
      modelo,
      etiqueta_ia: true
    });

    return new Response(JSON.stringify({ url: publicUrl, prompt_final: promptFinal }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
});
