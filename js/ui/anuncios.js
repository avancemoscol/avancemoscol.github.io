/**
 * Anuncios oficiales en modal: comunicados, encuestas y votaciones · Avancemos
 * - Se muestran al entrar a la red, uno tras otro.
 * - Los obligatorios no se pueden cerrar hasta responder.
 * - Admiten imagen, video y audio.
 */

import { el } from "../util/texto-seguro.js";
import { supabase } from "../supabase.js";
import { mostrarToast } from "./toast.js";

const BUCKETS_PUBLICOS = ["sitio", "media-publica", "ia-media"];

function urlMedia(m) {
  if (!m?.path) return null;
  if (/^https:\/\//.test(m.path)) return m.path;
  if (!BUCKETS_PUBLICOS.includes(m.bucket)) return null;
  return supabase.storage.from(m.bucket).getPublicUrl(m.path).data.publicUrl;
}

export function renderizarMediaAnuncio(media = []) {
  const cont = el("div", { className: "anuncio-media" });
  media.forEach(m => {
    const url = urlMedia(m);
    if (!url) return;
    if (m.tipo === "video") cont.appendChild(el("video", { src: url, controls: true, playsinline: true, preload: "metadata" }));
    else if (m.tipo === "audio") cont.appendChild(el("audio", { src: url, controls: true, preload: "none" }));
    else cont.appendChild(el("img", { src: url, alt: m.alt_text || "Imagen del anuncio", loading: "lazy" }));
  });
  return cont;
}

function renderizarResultados(res) {
  const total = res?.total || 0;
  const cont = el("div", { className: "anuncio-resultados" }, [
    el("p", { className: "anuncio-total", textContent: `${total} ${total === 1 ? "respuesta" : "respuestas"}` })
  ]);
  (res?.opciones || []).forEach(o => {
    const pct = total ? Math.round((o.votos / total) * 100) : 0;
    cont.appendChild(el("div", { className: "resultado-fila" }, [
      el("div", { className: "resultado-etiqueta" }, [el("span", { textContent: o.texto }), el("strong", { textContent: `${pct}% (${o.votos})` })]),
      el("div", { className: "resultado-barra" }, [el("div", { className: "resultado-relleno", style: `width: ${pct}%` })])
    ]));
  });
  return cont;
}

function mostrarAnuncio(a) {
  return new Promise((resolve) => {
    const esConsulta = a.tipo === "encuesta" || a.tipo === "votacion";
    const overlay = el("div", { className: "modal-overlay modal-anuncio", role: "dialog", "aria-modal": "true", "aria-label": a.titulo });
    const etiqueta = { comunicado: "📢 Comunicado oficial", encuesta: "📊 Encuesta", votacion: "🗳️ Votación" }[a.tipo] || "Anuncio";

    const cerrar = () => {
      overlay.classList.remove("abierto");
      document.body.classList.remove("sin-scroll");
      document.removeEventListener("keydown", onKey);
      setTimeout(() => { overlay.remove(); resolve(); }, 220);
    };
    // Los obligatorios no se cierran con Escape ni tocando fuera
    const onKey = (e) => { if (e.key === "Escape" && !a.obligatorio) cerrar(); };

    const cabecera = el("div", { className: "modal-cabecera" }, [
      el("span", { className: "chip chip-ambar", textContent: a.obligatorio ? `${etiqueta} · obligatoria` : etiqueta })
    ]);
    if (!a.obligatorio) {
      cabecera.appendChild(el("button", { className: "btn btn-fantasma btn-sm", "aria-label": "Cerrar", textContent: "✕", onclick: cerrar }));
    }

    const cuerpo = el("div", { className: "anuncio-cuerpo" }, [
      el("h3", { className: "anuncio-titulo", textContent: a.titulo }),
      a.cuerpo ? el("p", { className: "anuncio-texto", textContent: a.cuerpo }) : null,
      renderizarMediaAnuncio(a.media)
    ]);

    const zonaAccion = el("div", { className: "anuncio-accion" });
    const contenido = el("div", { className: "modal-contenido" }, [cabecera, cuerpo, zonaAccion]);
    overlay.appendChild(contenido);

    if (!esConsulta) {
      zonaAccion.appendChild(el("button", {
        className: "btn btn-primario btn-lg", style: "width: 100%;", textContent: "Entendido",
        onclick: async () => {
          await supabase.rpc("responder_anuncio", { p_anuncio_id: a.id, p_opciones: [] });
          cerrar();
        }
      }));
    } else {
      const form = el("form", { className: "anuncio-form" });
      const multiple = a.tipo === "encuesta" && a.multiple;
      const opciones = Array.isArray(a.opciones) ? a.opciones : [];
      opciones.forEach((o, i) => {
        const input = el("input", { type: multiple ? "checkbox" : "radio", name: "opcion", value: String(i), id: `op-${a.id}-${i}` });
        form.appendChild(el("label", { className: "anuncio-opcion", for: `op-${a.id}-${i}` }, [input, el("span", { textContent: o.texto })]));
      });
      let comentario = null;
      if (a.permite_comentario) {
        comentario = el("textarea", { className: "campo-textarea", rows: 2, maxlength: "500", placeholder: "Comentario (opcional)" });
        form.appendChild(comentario);
      }
      const btn = el("button", { type: "submit", className: "btn btn-primario btn-lg", style: "width: 100%;", textContent: a.tipo === "votacion" ? "Votar" : "Enviar respuesta" });
      form.appendChild(btn);
      form.addEventListener("submit", async (e) => {
        e.preventDefault();
        const elegidas = [...form.querySelectorAll("input[name=opcion]:checked")].map(x => parseInt(x.value, 10));
        if (!elegidas.length) return mostrarToast("Elige una opción para continuar.", "alerta");
        btn.disabled = true;
        const { error } = await supabase.rpc("responder_anuncio", {
          p_anuncio_id: a.id, p_opciones: elegidas, p_comentario: comentario ? comentario.value : null
        });
        if (error) {
          btn.disabled = false;
          return mostrarToast(error.message, "error");
        }
        mostrarToast(a.tipo === "votacion" ? "¡Tu voto quedó registrado!" : "¡Gracias por responder!", "exito");
        // Mostrar resultados si el anuncio lo permite
        const { data: res } = await supabase.rpc("resultados_anuncio", { p_anuncio_id: a.id });
        zonaAccion.innerHTML = "";
        if (res) zonaAccion.appendChild(renderizarResultados(res));
        zonaAccion.appendChild(el("button", { className: "btn btn-secundario", style: "width: 100%; margin-top: 1rem;", textContent: "Continuar", onclick: cerrar }));
      });
      zonaAccion.appendChild(form);
    }

    overlay.addEventListener("click", (e) => { if (e.target === overlay && !a.obligatorio && !esConsulta) cerrar(); });
    document.addEventListener("keydown", onKey);
    document.body.appendChild(overlay);
    document.body.classList.add("sin-scroll");
    requestAnimationFrame(() => overlay.classList.add("abierto"));
  });
}

export async function mostrarAnunciosPendientes() {
  const { data, error } = await supabase.rpc("anuncios_pendientes");
  if (error || !data?.length) return;
  for (const a of data) {
    await mostrarAnuncio(a);
  }
}

export { renderizarResultados };
