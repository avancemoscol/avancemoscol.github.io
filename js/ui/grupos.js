/**
 * Directorio de Grupos organizado (nacionales, tu departamento y por región) · Avancemos
 */

import { el } from "../util/texto-seguro.js";
import { obtenerGrupos } from "../servicios/grupos.js";

const ICONOS = { whatsapp: "🟢", telegram: "✈️", discord: "🎮" };
const ETIQUETA = { whatsapp: "WhatsApp", telegram: "Telegram", discord: "Discord" };
const URL_VALIDA = /^https:\/\/(chat\.whatsapp\.com|(www\.)?whatsapp\.com\/channel|t\.me|discord\.gg)\//;

let cache = null;
export async function cargarGrupos() {
  if (!cache) cache = obtenerGrupos();
  return cache;
}

/** Grupo principal de un departamento (para el mapa) */
export async function grupoDeDepartamento(deptoId) {
  const grupos = await cargarGrupos();
  return grupos.find(g => g.departamento_id === deptoId) || null;
}

export function tarjetaGrupo(g, destacado = false) {
  const valido = URL_VALIDA.test(g.url || "");
  return el("div", { className: `grupo-tarjeta${destacado ? " grupo-destacado" : ""}` }, [
    el("div", { className: "grupo-icono", "aria-hidden": "true", textContent: ICONOS[g.plataforma] || "💬" }),
    el("div", { className: "grupo-info" }, [
      el("strong", { textContent: g.departamento?.nombre && g.alcance !== "nacional" ? g.departamento.nombre : g.nombre }),
      el("span", { className: "grupo-meta", textContent: g.descripcion || `Grupo de ${ETIQUETA[g.plataforma] || "la comunidad"}` })
    ]),
    el("a", {
      className: "btn btn-primario btn-sm",
      href: valido ? g.url : "#",
      target: "_blank",
      rel: "noopener noreferrer",
      textContent: "Unirme",
      "aria-label": `Unirme a ${g.nombre}`
    })
  ]);
}

/**
 * Dibuja el directorio completo con buscador.
 * @param {HTMLElement} contenedor
 * @param {{ deptoUsuario?: string, deptoInicial?: string }} opciones
 */
export async function montarDirectorioGrupos(contenedor, opciones = {}) {
  contenedor.innerHTML = "";
  contenedor.appendChild(el("p", { className: "comentarios-estado", textContent: "Cargando grupos..." }));

  let grupos = [];
  try {
    grupos = await cargarGrupos();
  } catch (e) {
    contenedor.innerHTML = "";
    contenedor.appendChild(el("p", { style: "color: var(--error);", textContent: "No se pudieron cargar los grupos." }));
    return;
  }

  const nacionales = grupos.filter(g => !g.departamento_id);
  const territoriales = grupos.filter(g => g.departamento_id)
    .sort((a, b) => (a.departamento?.nombre || a.nombre).localeCompare(b.departamento?.nombre || b.nombre, "es"));

  contenedor.innerHTML = "";
  contenedor.appendChild(el("div", { className: "grupo-aviso" }, [
    el("strong", { textContent: "Privacidad: " }),
    el("span", { textContent: "en los grupos de WhatsApp los demás miembros pueden ver tu número. Telegram y Discord permiten participar sin mostrarlo." })
  ]));

  contenedor.appendChild(el("h3", { className: "grupo-titulo", textContent: "Comunidades nacionales" }));
  const gNac = el("div", { className: "grupos-grilla" });
  nacionales.forEach(g => gNac.appendChild(tarjetaGrupo(g)));
  contenedor.appendChild(gNac);

  const deptoFoco = opciones.deptoInicial || opciones.deptoUsuario;
  const propio = territoriales.find(g => g.departamento_id === deptoFoco);
  if (propio) {
    contenedor.appendChild(el("h3", { className: "grupo-titulo", textContent: opciones.deptoInicial ? "Grupo seleccionado" : "Tu departamento" }));
    const gProp = el("div", { className: "grupos-grilla" });
    gProp.appendChild(tarjetaGrupo(propio, true));
    contenedor.appendChild(gProp);
  }

  const buscador = el("input", {
    type: "search",
    className: "campo-input grupo-buscador",
    placeholder: "Buscar departamento...",
    "aria-label": "Buscar grupo por departamento"
  });
  contenedor.appendChild(el("h3", { className: "grupo-titulo", textContent: "Grupos por departamento" }));
  contenedor.appendChild(buscador);

  const regiones = {};
  territoriales.forEach(g => {
    const r = g.departamento?.region || "Otras";
    (regiones[r] = regiones[r] || []).push(g);
  });
  const listas = el("div", {});
  Object.keys(regiones).sort((a, b) => a.localeCompare(b, "es")).forEach(region => {
    const bloque = el("section", { className: "grupo-region" }, [el("h4", { textContent: region })]);
    const grilla = el("div", { className: "grupos-grilla" });
    regiones[region].forEach(g => {
      const t = tarjetaGrupo(g, g.departamento_id === deptoFoco);
      t.dataset.busqueda = (g.departamento?.nombre || g.nombre).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
      grilla.appendChild(t);
    });
    bloque.appendChild(grilla);
    listas.appendChild(bloque);
  });
  contenedor.appendChild(listas);

  buscador.addEventListener("input", () => {
    const q = buscador.value.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
    listas.querySelectorAll(".grupo-region").forEach(sec => {
      let visibles = 0;
      sec.querySelectorAll(".grupo-tarjeta").forEach(t => {
        const ok = !q || t.dataset.busqueda.includes(q);
        t.style.display = ok ? "" : "none";
        if (ok) visibles++;
      });
      sec.style.display = visibles ? "" : "none";
    });
  });
}
