/**
 * Vista de la Línea de Tiempo: cifras, "Lo que sigue" y "Lo que se ha hecho".
 * Se usa en la portada pública y en la pestaña "Avance" de la red social.
 */

import { el } from "../util/texto-seguro.js";
import { obtenerLineaTiempo } from "../servicios/linea-tiempo.js";

const ETIQUETA = { logrado: "Hecho", en_curso: "En curso", proximo: "Próximo" };
const fechaLarga = (f) => new Date(f).toLocaleDateString("es-CO", { day: "numeric", month: "long", year: "numeric", timeZone: "America/Bogota" });
const enlaceSeguro = (u) => /^https:\/\//.test(u || "") ? u : null;

function cifra(valor, texto) {
  return el("div", { className: "lt-cifra" }, [
    el("strong", { textContent: Number(valor || 0).toLocaleString("es-CO") }),
    el("span", { textContent: texto })
  ]);
}

function item(h) {
  const meta = [fechaLarga(h.fecha), h.departamento, h.lugar].filter(Boolean).join(" · ");
  const url = enlaceSeguro(h.enlace);
  return el("article", { className: `lt-item lt-${h.estado}` }, [
    el("span", { className: "lt-punto", "aria-hidden": "true" }),
    el("div", { className: "lt-cuerpo" }, [
      el("div", { className: "lt-cabecera" }, [
        el("span", { className: `chip ${h.estado === "logrado" ? "chip-turquesa" : "chip-ambar"}`, textContent: h.origen === "evento" ? (h.estado === "logrado" ? "Evento realizado" : "Evento") : ETIQUETA[h.estado] }),
        el("time", { textContent: meta })
      ]),
      el("h3", { textContent: h.titulo }),
      h.descripcion ? el("p", { textContent: h.descripcion }) : null,
      url ? el("a", { href: url, target: "_blank", rel: "noopener noreferrer", textContent: "Ver más →" }) : null,
      h.origen === "evento" && h.estado === "proximo" ? el("a", { href: "eventos.html", textContent: "Ver evento →" }) : null
    ])
  ]);
}

function columna(titulo, lista, vacio) {
  return el("section", { className: "lt-columna" }, [
    el("h2", { textContent: titulo }),
    lista.length ? el("div", { className: "lt-lista" }, lista.map(item)) : el("p", { className: "lt-vacio", textContent: vacio })
  ]);
}

export async function montarLineaTiempo(cont, { limite = 30 } = {}) {
  cont.replaceChildren(el("div", { className: "esqueleto", style: "height: 200px;" }));
  try {
    const { proximo, historial, cifras } = await obtenerLineaTiempo(limite);
    cont.replaceChildren(el("div", { className: "lt" }, [
      el("div", { className: "lt-cifras" }, [
        cifra(cifras.miembros, "personas en la red"),
        cifra(cifras.departamentos, "departamentos con presencia"),
        cifra(cifras.eventos_realizados, "eventos realizados"),
        cifra(cifras.eventos_proximos, "eventos por venir")
      ]),
      columna("Lo que sigue", proximo, "Pronto anunciaremos los próximos pasos."),
      columna("Lo que se ha hecho", historial, "Aquí irá quedando el historial del movimiento.")
    ]));
  } catch (e) {
    cont.replaceChildren(el("p", { className: "lt-vacio", textContent: "No se pudo cargar el avance del movimiento." }));
  }
}
