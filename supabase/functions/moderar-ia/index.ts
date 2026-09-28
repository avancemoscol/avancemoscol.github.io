import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { tokenGoogle, urlModelo } from "../_shared/vertex.ts";
import { obtenerClienteAdmin } from "../_shared/auth.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    const { table, record } = payload;
    const texto = record?.contenido || record?.descripcion || record?.texto || "";

    if (!texto) {
      return new Response(JSON.stringify({ ignorado: true }), { headers: corsHeaders });
    }

    const token = await tokenGoogle();
    const endpoint = urlModelo("global", "gemini-2.5-flash-lite", "generateContent");

    const promptMod = `
Analiza el siguiente texto publicado en una red cívico-política en Colombia. Devuelve SOLO un JSON con este formato exacto:
{
  "riesgo": "bajo" | "medio" | "alto",
  "categorias": ["ninguna" | "ataque_personal" | "odio" | "violencia" | "desinformacion" | "datos_personales" | "spam"],
  "motivo": "explicación muy breve de máximo una frase",
  "sugerencia": "aprobar" | "revisar" | "rechazar"
}

Texto a analizar:
"${texto}"
`;

    const resVertex = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: promptMod }] }],
        generationConfig: { responseMimeType: "application/json" }
      })
    });

    if (resVertex.ok) {
      const gcpJson = await resVertex.json();
      const rawRes = gcpJson.candidates?.[0]?.content?.parts?.[0]?.text;
      if (rawRes) {
        const iaAnalisis = JSON.parse(rawRes);
        const supabaseAdmin = obtenerClienteAdmin();
        await supabaseAdmin
          .from(table)
          .update({ ia_moderacion: iaAnalisis })
          .eq("id", record.id);
      }
    }

    return new Response(JSON.stringify({ procesado: true }), { headers: corsHeaders });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: corsHeaders });
  }
});
