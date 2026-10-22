/**
 * Línea de tiempo · Panel Administrativo
 * El administrador publica lo que se ha hecho y lo que sigue.
 */

import { el } from "../../util/texto-seguro.js";
import { mostrarToast } from "../../ui/toast.js";
import { abrirModal } from "../../ui/modal.js";
import * as api from "../../servicios/admin.js";

const ESTADOS = [["logrado", "Hecho"], ["en_curso", "En curso"], ["proximo", "Próximo"]];
const hoy = () => new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 10);

function campo(etiqueta, control) {
  return el("label", { className: "campo" }, [el("span", { className: "campo-etiqueta", textContent: etiqueta }), control]);
}
function input(attrs = {}, valor = "") { const i = el("input", { className: "campo-input", ...attrs }); i.value = valor ?? ""; return i; }
function select(opciones, valor = "") {
  const s = el("select", { className: "campo-select" }, opciones.map(([v, t]) => el("option", { value: v, textContent: t })));
  s.value = valor; return s;
}

export async function montarHitos(cont, ctx) {
  cont.replaceChildren();
  const lista = el("div", { className: "admin-lista" });
  cont.append(
    el("div", { className: "admin-barra" }, [
      el("button", { className: "btn btn-primario", textContent: "➕ Nuevo hito", onclick: () => editar({ estado: "logrado", fecha: hoy(), publicado: true }, ctx, cargar) })
    ]),
    lista
  );

  async function cargar() {
    lista.replaceChildren(el("div", { className: "esqueleto", style: "height: 100px;" }));
    try {
      const hitos = await api.listarHitos();
      lista.replaceChildren();
      if (!hitos.length) return lista.appendChild(el("div", { className: "tarjeta", style: "text-align:center;padding:2rem;color:var(--texto-suave);", textContent: "Aún no hay hitos. Crea el primero." }));
      hitos.forEach(h => lista.appendChild(el("div", { className: "aprobacion-tarjeta" }, [
        el("div", { className: "aprobacion-cabecera" }, [
          el("div", {}, [
            el("strong", { textContent: h.titulo }),
            el("div", { style: "font-size:0.8rem;color:var(--texto-suave);", textContent: `${ESTADOS.find(e => e[0] === h.estado)[1]} · ${h.fecha}` })
          ]),
          el("span", { className: `chip ${h.publicado ? "chip-turquesa" : "chip-ambar"}`, textContent: h.publicado ? "publicado" : "oculto" })
        ]),
        h.descripcion ? el("p", { style: "white-space:pre-wrap;font-size:0.9rem;", textContent: h.descripcion }) : null,
        el("div", { className: "aprobacion-acciones" }, [
          el("button", { className: "btn btn-secundario btn-sm", textContent: "Editar", onclick: () => editar(h, ctx, cargar) }),
          el("button", {
            className: "btn btn-secundario btn-sm", textContent: h.publicado ? "Ocultar" : "Publicar",
            onclick: async () => { try { await api.guardarHito(h.id, { ...h, publicado: !h.publicado }); cargar(); } catch (e) { mostrarToast(e.message, "error"); } }
          }),
          el("button", {
            className: "btn btn-peligro btn-sm", textContent: "Eliminar",
            onclick: async () => { if (!confirm("¿Eliminar este hito?")) return; try { await api.eliminarHito(h.id); cargar(); } catch (e) { mostrarToast(e.message, "error"); } }
          })
        ])
      ])));
    } catch (e) { lista.replaceChildren(el("div", { className: "tarjeta", style: "color:var(--error);", textContent: e.message })); }
  }
  cargar();
}

function editar(h, ctx, recargar) {
  const titulo = input({ maxlength: "160" }, h.titulo);
  const descripcion = el("textarea", { className: "campo-textarea", rows: 4, placeholder: "Qué se hizo o qué viene, en pocas líneas" });
  descripcion.value = h.descripcion || "";
  const estado = select(ESTADOS, h.estado);
  const fecha = input({ type: "date" }, h.fecha);
  const depto = select([["", "Nacional"], ...(ctx.departamentos || []).map(d => [d.id, d.nombre])], h.departamento_id || "");
  const enlace = input({ type: "url", placeholder: "https://… (opcional)" }, h.enlace || "");
  const publicado = el("input", { type: "checkbox" }); publicado.checked = h.publicado !== false;

  abrirModal({
    titulo: h.id ? "Editar hito" : "Nuevo hito",
    contenidoNodo: el("div", { className: "admin-form" }, [
      campo("Título", titulo), campo("Descripción", descripcion),
      el("div", { className: "admin-form-grid" }, [campo("Estado", estado), campo("Fecha", fecha)]),
      campo("Territorio", depto), campo("Enlace", enlace),
      el("label", { className: "admin-check" }, [publicado, " Visible para todos"])
    ]),
    acciones: [
      { texto: "Cancelar", tipo: "secundario" },
      {
        texto: "Guardar", tipo: "primario",
        onClick: async (cerrar) => {
          try {
            await api.guardarHito(h.id, {
              titulo: titulo.value, descripcion: descripcion.value, estado: estado.value, fecha: fecha.value,
              departamento_id: depto.value, enlace: enlace.value, publicado: publicado.checked
            });
            mostrarToast("Hito guardado.", "exito");
            cerrar(); recargar();
          } catch (e) { mostrarToast(e.message, "error"); }
        }
      }
    ]
  });
}
