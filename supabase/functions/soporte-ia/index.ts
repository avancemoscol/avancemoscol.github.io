import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { tokenGoogle, urlModelo } from "../_shared/vertex.ts";

const PROMPT_SISTEMA_SOPORTE = `
Eres el Asistente Oficial del Movimiento Político de Centro 'Avancemos' en Colombia.
Tu función es orientar a ciudadanos, simpatizantes, voluntarios y líderes de manera clara, amable, respetuosa e imparcial.
Reglas clave:
- Ideología: Centro político en Colombia. Defendemos la Constitución de 1991, el rigor técnico, la evidencia empírica, el diálogo, la justicia social y el libre emprendimiento. No somos tibios; tomamos posición basada en evidencia.
- Organización: 32 departamentos y Bogotá D.C.
- Proceso de ingreso: Es 100% gratuito. Tras registrarse, los moderadores del departamento revisan la cuenta en 24 a 48 horas.
- Grupos de WhatsApp: Exclusivos para miembros aprobados para proteger los teléfonos y la seguridad de los líderes.
- Verificación: Insignia azul (identidad confirmada en videollamada), dorada (líderes oficiales) y gris (servidores de elección popular).
- Tono: Cercano, propositivo, en español de Colombia, constructivo y sin agresividad.
- Responde en máximo 120 palabras, en texto plano (puedes usar **negritas** y viñetas con guion).
Si el usuario tiene un reclamo específico o problema técnico, invítalo a radicar un caso formal en la pestaña "Radicar Caso".
`;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { pregunta, usuario } = await req.json();

    if (!pregunta || typeof pregunta !== "string" || pregunta.length > 1000) {
      return new Response(JSON.stringify({ error: "La pregunta es obligatoria (máximo 1000 caracteres)." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // Token Google Vertex AI
    const token = await tokenGoogle();
    const endpoint = urlModelo("global", "gemini-2.5-flash", "generateContent");

    const payload = {
      contents: [
        {
          role: "user",
          parts: [{ text: `${PROMPT_SISTEMA_SOPORTE}\n\nPregunta del ciudadano: ${pregunta}` }]
        }
      ],
      generationConfig: {
        temperature: 0.3,
        maxOutputTokens: 1024,
        // Sin razonamiento interno: respuestas rápidas y que no se corten
        thinkingConfig: { thinkingBudget: 0 }
      }
    };

    const resGcp = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    if (!resGcp.ok) {
      const errTxt = await resGcp.text();
      throw new Error(`Vertex AI error ${resGcp.status}: ${errTxt}`);
    }

    const gcpData = await resGcp.json();
    const respuesta = gcpData.candidates?.[0]?.content?.parts?.[0]?.text || "No fue posible generar una respuesta en este momento.";

    return new Response(JSON.stringify({ respuesta }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
});
