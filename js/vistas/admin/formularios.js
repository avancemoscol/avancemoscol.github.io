/**
 * Formularios, encuestas y votaciones con enlace compartible · Panel Administrativo
 * Cada respuesta llega "pendiente" y solo cuenta en los resultados cuando se aprueba.
 */

import { el } from "../../util/texto-seguro.js";
import { mostrarToast } from "../../ui/toast.js";
import { abrirModal } from "../../ui/modal.js";
import * as api from "../../servicios/admin.js";

const TIPOS_CAMPO = [
  ["texto", "Texto corto"], ["parrafo", "Texto largo"], ["opcion", "Una opción"], ["multiple", "Varias opciones"],
  ["lista", "Lista desplegable"], ["numero", "Número"], ["fecha", "Fecha"], ["correo", "Correo"], ["telefono", "Teléfono"]
];
const CON_OPCIONES = ["opcion", "multiple", "lista"];
const TIPOS_FORM = [["formulario", "Formulario"], ["encuesta", "Encuesta"], ["votacion", "Votación (requiere cuenta)"]];
const fecha = (f) => f ? new Date(f).toLocaleString("es-CO", { dateStyle: "medium", timeStyle: "short" }) : "—";
const aLocal = (f) => f ? new Date(new Date(f).getTime() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16) : "";
const nuevoId = () => "q" + Math.random().toString(36).slice(2, 8);
const enlaceDe = (slug) => new URL(`formulario.html?f=${encodeURIComponent(slug)}`, location.href).href;

function campo(etiqueta, control) {
  return el("label", { className: "campo" }, [el("span", { className: "campo-etiqueta", textContent: etiqueta }), control]);
}
function input(attrs = {}, valor = "") { const i = el("input", { className: "campo-input", ...attrs }); i.value = valor ?? ""; return i; }
function textarea(valor = "", attrs = {}) { const t = el("textarea", { className: "campo-textarea", rows: 3, ...attrs }); t.value = valor ?? ""; return t; }
function select(opciones, valor = "") {
  const s = el("select", { className: "campo-select" }, opciones.map(([v, t]) => el("option", { value: v, textContent: t })));
  s.value = valor; return s;
}
function check(valor) { const c = el("input", { type: "checkbox" }); c.checked = Boolean(valor); return c; }

async function copiar(texto) {
  try { await navigator.clipboard.writeText(texto); mostrarToast("Enlace copiado.", "exito"); }
  catch { prompt("Copia el enlace:", texto); }
}

export async function montarFormularios(cont) {
  cont.innerHTML = "";
  const lista = el("div", { className: "admin-lista" });
  cont.append(
    el("p", { className: "ajustes-ayuda", textContent: "Crea formularios, encuestas o votaciones y comparte el enlace. Las respuestas llegan como pendientes: tú las apruebas o rechazas, y solo las aprobadas cuentan en los resultados." }),
    el("div", { className: "admin-barra" }, [
      el("button", { className: "btn btn-primario", textContent: "📝 Nuevo formulario", onclick: () => editar({ tipo: "formulario" }, cargar) }),
      el("button", { className: "btn btn-secundario", textContent: "📊 Nueva encuesta", onclick: () => editar({ tipo: "encuesta" }, cargar) }),
      el("button", { className: "btn btn-secundario", textContent: "🗳️ Nueva votación", onclick: () => editar({ tipo: "votacion" }, cargar) })
    ]),
    lista
  );

  async function cargar() {
    lista.innerHTML = "<div class='esqueleto' style='height: 120px;'></div>";
    try {
      const formularios = await api.listarFormularios();
      lista.innerHTML = "";
      if (!formularios.length) return lista.appendChild(el("div", { className: "tarjeta", style: "text-align:center;padding:2rem;color:var(--texto-suave);", textContent: "Aún no hay formularios." }));
      formularios.forEach(f => {
        const vigente = f.abierto && (!f.cierra_en || new Date(f.cierra_en) > new Date());
        lista.appendChild(el("div", { className: "aprobacion-tarjeta" }, [
          el("div", { className: "aprobacion-cabecera" }, [
            el("div", {}, [
              el("strong", { textContent: f.titulo }),
              el("div", { style: "font-size:0.8rem;color:var(--texto-suave);", textContent: `${f.tipo} · ${f.campos.length} preguntas · ${f.pendientes} pendientes · ${f.aprobadas} aprobadas · ${f.rechazadas} rechazadas · ${fecha(f.created_at)}` })
            ]),
            el("span", { className: `chip ${vigente ? "chip-turquesa" : "chip-ambar"}`, textContent: vigente ? "recibiendo" : "cerrado" })
          ]),
          input({ readonly: "true" }, enlaceDe(f.slug)),
          el("div", { className: "aprobacion-acciones" }, [
            el("button", { className: "btn btn-primario btn-sm", textContent: "🔗 Copiar enlace", onclick: () => copiar(enlaceDe(f.slug)) }),
            el("button", { className: "btn btn-secundario btn-sm", textContent: `Revisar respuestas (${f.pendientes})`, onclick: () => revisar(f, cargar) }),
            el("button", { className: "btn btn-secundario btn-sm", textContent: "Resultados", onclick: () => verResultados(f) }),
            el("button", { className: "btn btn-secundario btn-sm", textContent: "Editar", onclick: () => editar(f, cargar) }),
            el("button", {
              className: "btn btn-secundario btn-sm", textContent: f.abierto ? "Cerrar" : "Reabrir",
              onclick: async () => { try { await api.guardarFormulario(f.id, { ...f, abierto: !f.abierto }); cargar(); } catch (e) { mostrarToast(e.message, "error"); } }
            }),
            el("button", {
              className: "btn btn-peligro btn-sm", textContent: "Eliminar",
              onclick: async () => { if (!confirm("¿Eliminar este formulario y todas sus respuestas?")) return; try { await api.eliminarFormulario(f.id); cargar(); } catch (e) { mostrarToast(e.message, "error"); } }
            })
          ])
        ]));
      });
    } catch (e) { lista.innerHTML = ""; lista.appendChild(el("div", { className: "tarjeta", style: "color:var(--error);", textContent: e.message })); }
  }
  cargar();
}

function editar(f, recargar) {
  const tipo = select(TIPOS_FORM, f.tipo);
  const titulo = input({ maxlength: "160" }, f.titulo);
  const descripcion = textarea(f.descripcion, { rows: 3, placeholder: "Explica de qué trata y para qué se usará" });
  const cierra = input({ type: "datetime-local" }, aLocal(f.cierra_en));
  const login = check(f.requiere_login);
  const resultados = check(f.mostrar_resultados);
  const mensaje = input({ maxlength: "300" }, f.mensaje_final || "");
  const bloqueado = Boolean(f.id) && (f.pendientes + f.aprobadas + f.rechazadas) > 0;

  let campos = (f.campos?.length ? f.campos : [{ id: nuevoId(), tipo: f.tipo === "votacion" ? "opcion" : "texto", etiqueta: "", requerido: true, opciones: [] }])
    .map(c => ({ ...c, opciones: c.opciones || [] }));
  const zonaCampos = el("div", { className: "admin-form" });
  const pintar = () => {
    zonaCampos.innerHTML = "";
    campos.forEach((c, i) => {
      const t = select(TIPOS_CAMPO, c.tipo);
      const e = input({ placeholder: "Pregunta" }, c.etiqueta);
      const r = check(c.requerido);
      const ops = textarea(c.opciones.join("\n"), { rows: 3, placeholder: "Una opción por línea" });
      const cajaOps = el("div", {}, [campo("Opciones", ops)]);
      cajaOps.style.display = CON_OPCIONES.includes(c.tipo) ? "" : "none";
      t.disabled = e.disabled = ops.disabled = bloqueado;
      t.addEventListener("change", () => { c.tipo = t.value; cajaOps.style.display = CON_OPCIONES.includes(t.value) ? "" : "none"; });
      e.addEventListener("input", () => { c.etiqueta = e.value; });
      r.addEventListener("change", () => { c.requerido = r.checked; });
      ops.addEventListener("input", () => { c.opciones = ops.value.split("\n").map(x => x.trim()).filter(Boolean); });
      zonaCampos.appendChild(el("div", { className: "tarjeta", style: "padding:0.75rem;" }, [
        el("div", { className: "admin-form-grid" }, [campo(`Pregunta ${i + 1}`, e), campo("Tipo de respuesta", t)]),
        cajaOps,
        el("div", { style: "display:flex;gap:0.75rem;align-items:center;justify-content:space-between;margin-top:0.5rem;" }, [
          el("label", { className: "admin-check" }, [r, " Obligatoria"]),
          bloqueado ? null : el("button", { className: "btn btn-fantasma btn-sm", textContent: "Quitar", onclick: () => { campos.splice(i, 1); pintar(); } })
        ])
      ]));
    });
    if (!bloqueado) zonaCampos.appendChild(el("button", {
      className: "btn btn-secundario btn-sm", textContent: "+ Agregar pregunta",
      onclick: () => { campos.push({ id: nuevoId(), tipo: "texto", etiqueta: "", requerido: false, opciones: [] }); pintar(); }
    }));
  };
  pintar();

  abrirModal({
    titulo: f.id ? "Editar formulario" : "Nuevo formulario",
    contenidoNodo: el("div", { className: "admin-form" }, [
      bloqueado ? el("p", { className: "ajustes-ayuda", textContent: "Ya hay respuestas: las preguntas no se pueden cambiar, pero sí el resto de los datos." }) : null,
      campo("Tipo", tipo), campo("Título", titulo), campo("Descripción", descripcion),
      zonaCampos,
      campo("Recibe respuestas hasta (opcional)", cierra),
      el("label", { className: "admin-check" }, [login, " Exigir cuenta de Avancemos para responder (una respuesta por persona; siempre activo en votaciones)"]),
      el("label", { className: "admin-check" }, [resultados, " Mostrar resultados aprobados a quien tenga el enlace"]),
      campo("Mensaje al enviar", mensaje)
    ]),
    acciones: [
      { texto: "Cancelar", tipo: "secundario" },
      {
        texto: "Guardar", tipo: "primario",
        onClick: async (cerrar) => {
          try {
            await api.guardarFormulario(f.id, {
              tipo: tipo.value, titulo: titulo.value, descripcion: descripcion.value, campos,
              abierto: f.abierto !== false, cierra_en: cierra.value ? new Date(cierra.value).toISOString() : "",
              requiere_login: login.checked, mostrar_resultados: resultados.checked, mensaje_final: mensaje.value
            });
            mostrarToast("Formulario guardado.", "exito");
            cerrar(); recargar();
          } catch (e) { mostrarToast(e.message, "error"); }
        }
      }
    ]
  });
}

function revisar(f, recargar) {
  const zona = el("div", { className: "admin-lista" });
  const filtro = select([["pendiente", "Pendientes"], ["aprobada", "Aprobadas"], ["rechazada", "Rechazadas"]], "pendiente");
  const titulos = Object.fromEntries(f.campos.map(c => [c.id, c.etiqueta]));

  async function cargar() {
    zona.innerHTML = "<div class='esqueleto' style='height:80px;'></div>";
    try {
      const rs = await api.listarRespuestasFormulario(f.id, filtro.value);
      zona.innerHTML = "";
      if (!rs.length) return zona.appendChild(el("p", { className: "ajustes-ayuda", textContent: "No hay respuestas en este estado." }));
      rs.forEach(r => {
        const acciones = ["aprobada", "rechazada", "pendiente"].filter(e => e !== r.estado).map(e => el("button", {
          className: `btn btn-sm ${e === "aprobada" ? "btn-primario" : "btn-secundario"}`,
          textContent: { aprobada: "✓ Aprobar", rechazada: "✕ Rechazar", pendiente: "↺ Devolver a pendiente" }[e],
          onclick: async () => { try { await api.revisarRespuestaFormulario(r.id, e); cargar(); recargar(); } catch (er) { mostrarToast(er.message, "error"); } }
        }));
        zona.appendChild(el("div", { className: "aprobacion-tarjeta" }, [
          el("div", { style: "font-size:0.8rem;color:var(--texto-suave);", textContent: [r.nombre, r.contacto, r.usuario ? "@" + r.usuario : null, fecha(r.created_at)].filter(Boolean).join(" · ") }),
          ...Object.entries(r.respuestas).map(([id, v]) => el("p", { style: "margin:0.25rem 0;" }, [
            el("strong", { textContent: (titulos[id] || id) + ": " }), Array.isArray(v) ? v.join(", ") : String(v)
          ])),
          el("div", { className: "aprobacion-acciones" }, acciones)
        ]));
      });
    } catch (e) { zona.innerHTML = ""; zona.appendChild(el("p", { style: "color:var(--error);", textContent: e.message })); }
  }
  filtro.addEventListener("change", cargar);
  abrirModal({ titulo: `Respuestas · ${f.titulo}`, contenidoNodo: el("div", { className: "admin-form" }, [filtro, zona]) });
  cargar();
}

async function verResultados(f) {
  const zona = el("div", { className: "admin-form" });
  abrirModal({ titulo: `Resultados · ${f.titulo}`, contenidoNodo: zona });
  try {
    const res = await api.resultadosFormulario(f.slug);
    zona.appendChild(el("p", { textContent: `${res.total} respuestas aprobadas.` }));
    if (!res.preguntas.length) zona.appendChild(el("p", { className: "ajustes-ayuda", textContent: "Este formulario no tiene preguntas de opciones; revisa las respuestas una a una." }));
    res.preguntas.forEach(p => {
      zona.appendChild(el("strong", { textContent: p.etiqueta }));
      p.opciones.forEach(o => {
        const pct = res.total ? Math.round(o.votos * 100 / res.total) : 0;
        zona.appendChild(el("div", { style: "margin:0.35rem 0;" }, [
          el("div", { style: "display:flex;justify-content:space-between;font-size:0.9rem;", textContent: "" }, [el("span", { textContent: o.texto }), el("span", { textContent: `${o.votos} (${pct}%)` })]),
          el("div", { style: "background:var(--borde-suave);border-radius:6px;height:8px;overflow:hidden;" }, [el("div", { style: `width:${pct}%;height:100%;background:var(--turquesa, #0d9488);` })])
        ]));
      });
    });
  } catch (e) { zona.appendChild(el("p", { style: "color:var(--error);", textContent: e.message })); }
}
