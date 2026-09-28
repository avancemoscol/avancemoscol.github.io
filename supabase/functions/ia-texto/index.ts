import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { tokenGoogle, urlModelo } from "../_shared/vertex.ts";
import { exigirModerador } from "../_shared/auth.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const denegado = await exigirModerador(req, corsHeaders);
  if (denegado) return denegado;

  try {
    const { accion, texto } = await req.json();

    if (!texto) {
      return new Response(JSON.stringify({ error: "Falta el texto de entrada." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    const token = await tokenGoogle();
    const endpoint = urlModelo("global", "gemini-2.5-flash", "generateContent");

    let promptSistema = "";
    if (accion === "mejorar_prompt") {
      promptSistema = "Mejora y expande la siguiente descripción para generar una imagen institucional en inglés, estilo editorial documental sin personas reconocibles ni texto, con luz natural cálida y tonos sutiles de turquesa y ámbar:";
    } else if (accion === "texto_alternativo") {
      promptSistema = "Genera un texto alternativo conciso y accesible en español (máx 120 caracteres) para personas con discapacidad visual a partir de la siguiente descripción:";
    } else {
      promptSistema = "Revisa y sugiere mejoras de redacción institucional constructiva para el siguiente texto:";
    }

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
            parts: [{ text: `${promptSistema}\n\n${texto}` }]
          }
        ]
      })
    });

    if (!resVertex.ok) {
      throw new Error(`Vertex error ${resVertex.status}`);
    }

    const json = await resVertex.json();
    const resultado = json.candidates?.[0]?.content?.parts?.[0]?.text?.trim() || texto;

    return new Response(JSON.stringify({ resultado }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
});
