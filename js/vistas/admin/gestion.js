/**
 * Módulos de gestión del Panel Administrativo · Avancemos
 * Usuarios y roles · Publicaciones y comentarios · Eventos · Anuncios (comunicados,
 * encuestas y votaciones) · Grupos.
 */

import { el } from "../../util/texto-seguro.js";
import { supabase } from "../../supabase.js";
import { mostrarToast } from "../../ui/toast.js";
import { abrirModal } from "../../ui/modal.js";
import { renderizarInsignia } from "../../ui/avatar.js";
import { obtenerUrlMedia } from "../../servicios/publicaciones.js";
import { obtenerGrupos } from "../../servicios/grupos.js";
import { comprimirImagenWebP } from "../../util/imagenes.js";
import { comprimirAudio } from "../../util/audio.js";
import { renderizarResultados, renderizarMediaAnuncio } from "../../ui/anuncios.js";
import * as api from "../../servicios/admin.js";
import { AREAS_APOYO, nombreAreaApoyo } from "../../util/areas-apoyo.js";

const ROLES = [
  ["simpatizante", "Simpatizante"], ["voluntario", "Voluntario"], ["lider", "Líder"],
  ["moderador", "Moderador (departamento)"], ["admin_departamental", "Admin departamental"], ["admin_nacional", "Admin nacional"]
];
const ESTADOS_CUENTA = ["pendiente", "activo", "suspendido", "rechazado", "baneado"];
const fecha = (f, hora = false) => f ? new Date(f).toLocaleString("es-CO", hora ? { dateStyle: "medium", timeStyle: "short" } : { dateStyle: "medium" }) : "—";
const aLocal = (f) => f ? new Date(new Date(f).getTime() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16) : "";

function campo(etiqueta, control) {
  return el("label", { className: "campo" }, [el("span", { className: "campo-etiqueta", textContent: etiqueta }), control]);
}
function input(attrs = {}, valor = "") {
  const i = el("input", { className: "campo-input", ...attrs });
  i.value = valor ?? "";
  return i;
}
function select(opciones, valor = "", attrs = {}) {
  const { disabled, ...resto } = attrs;
  const s = el("select", { className: "campo-select", ...resto }, opciones.map(([v, t]) => el("option", { value: v, textContent: t })));
  s.value = valor ?? "";
  s.disabled = Boolean(disabled);
  return s;
}
function textarea(valor = "", attrs = {}) {
  const t = el("textarea", { className: "campo-textarea", rows: 3, ...attrs });
  t.value = valor ?? "";
  return t;
}
function barra(...hijos) { return el("div", { className: "admin-barra" }, hijos); }
function vacio(txt) { return el("div", { className: "tarjeta", style: "text-align: center; padding: 2rem; color: var(--texto-suave);", textContent: txt }); }
function error(cont, e) {
  cont.innerHTML = "";
  cont.appendChild(el("div", { className: "tarjeta", style: "color: var(--error);", textContent: e.message || String(e) }));
}

// Sube un archivo del panel al bucket público "sitio" en el formato más eficiente
async function subirMediaSitio(archivo, carpeta) {
  let final = archivo;
  let tipo = "imagen";
  if (archivo.type.startsWith("image/") && archivo.type !== "image/gif") {
    final = (await comprimirImagenWebP(archivo)).archivo;
  } else if (archivo.type.startsWith("audio/")) {
    final = (await comprimirAudio(archivo)).archivo;
    tipo = "audio";
  } else if (archivo.type.startsWith("video/")) {
    if (archivo.size > 50 * 1024 * 1024) throw new Error("El video supera 50 MB.");
    tipo = "video";
  }
  const ext = (final.name.split(".").pop() || "bin").toLowerCase();
  const ruta = `${carpeta}/${Date.now()}_${crypto.randomUUID().slice(0, 8)}.${ext}`;
  const { error: e } = await supabase.storage.from("sitio").upload(ruta, final, { contentType: final.type });
  if (e) throw e;
  return { tipo, bucket: "sitio", path: ruta };
}

// ===========================================================================
// USUARIOS Y ROLES
// ===========================================================================
export async function montarUsuarios(cont, ctx) {
  cont.innerHTML = "";
  const busqueda = input({ type: "search", placeholder: "Buscar por nombre, usuario o correo..." });
  const estado = select([["", "Todos los estados"], ...ESTADOS_CUENTA.map(e => [e, e])]);
  const area = select([["", "Todas las áreas de apoyo"], ...AREAS_APOYO]);
  const lista = el("div", { className: "admin-lista" });
  cont.append(barra(busqueda, estado, area), lista);

  let t;
  const cargar = async () => {
    lista.innerHTML = "<div class='esqueleto' style='height: 120px;'></div>";
    try {
      const usuarios = await api.listarUsuarios(busqueda.value.trim(), ctx.depto(), estado.value, area.value);
      lista.innerHTML = "";
      if (!usuarios.length) return lista.appendChild(vacio("No hay usuarios con esos filtros."));
      const tabla = el("table", { className: "admin-tabla" }, [
        el("thead", {}, [el("tr", {}, ["Usuario", "Nombre", "Correo", "Territorio", "Puede ayudar en", "Estado", "Roles", ""].map(h => el("th", { textContent: h })))])
      ]);
      const tbody = el("tbody");
      usuarios.forEach(u => {
        tbody.appendChild(el("tr", {}, [
          el("td", {}, [el("strong", { textContent: `@${u.username}` }), " ", renderizarInsignia(u.insignia)]),
          el("td", {}, [u.nombre, u.cargo_titulo ? el("div", { className: "etiqueta-cargo", textContent: u.cargo_titulo }) : null]),
          el("td", { textContent: u.correo || "—" }),
          el("td", { textContent: [u.municipio, u.departamento].filter(Boolean).join(", ") || "—" }),
          el("td", { textContent: nombreAreaApoyo(u.area_apoyo, u.area_apoyo_otro) || "—" }),
          el("td", {}, [el("span", { className: `chip ${u.estado === "activo" ? "chip-turquesa" : "chip-ambar"}`, textContent: u.estado })]),
          el("td", { textContent: (u.roles || []).map(r => r.rol + (r.departamento_id ? ` (${r.departamento_id})` : "")).join(", ") || "—" }),
          el("td", {}, [el("button", { className: "btn btn-secundario btn-sm", textContent: "Ver / editar", onclick: () => editarUsuario(u, ctx, cargar) })])
        ]));
      });
      tabla.appendChild(tbody);
      lista.appendChild(el("div", { className: "admin-tabla-scroll" }, [tabla]));
    } catch (e) { error(lista, e); }
  };
  busqueda.addEventListener("input", () => { clearTimeout(t); t = setTimeout(cargar, 350); });
  estado.addEventListener("change", cargar);
  area.addEventListener("change", cargar);
  cargar();
}

function editarUsuario(u, ctx, recargar) {
  const nombre = input({}, u.nombre);
  const etiqueta = input({ maxlength: "60", placeholder: "Ej. Líder de Bogotá · Localidad de Suba" }, u.cargo_titulo);
  const bio = textarea(u.bio, { maxlength: "280" });
  const ocupacion = input({}, u.ocupacion);
  const telefono = input({ type: "tel" }, u.telefono);
  const estado = select(ESTADOS_CUENTA.map(e => [e, e]), u.estado);
  const depto = select([["", "—"], ...ctx.departamentos.map(d => [d.id, d.nombre])], u.departamento_id, { disabled: !ctx.permisos.es_admin_nacional });
  const insignia = select([["ninguna", "Sin insignia"], ["azul", "Azul · identidad verificada"], ["dorada", "Dorada · vocería oficial"], ["gris", "Gris · servidor público"]], u.insignia);
  const notas = textarea(u.notas_admin, { placeholder: "Notas internas (solo administradores)" });
  const areaApoyo = select([["", "Sin indicar"], ...AREAS_APOYO], u.area_apoyo || "");
  const areaOtro = input({ maxlength: "120", placeholder: "¿Cuál?" }, u.area_apoyo_otro);
  const campoAreaOtro = campo("Otra área", areaOtro);
  campoAreaOtro.style.display = areaApoyo.value === "otro" ? "" : "none";
  areaApoyo.addEventListener("change", () => { campoAreaOtro.style.display = areaApoyo.value === "otro" ? "" : "none"; });

  // Roles actuales + formulario para agregar
  const listaRoles = el("div", { className: "admin-roles" });
  const pintarRoles = (roles) => {
    listaRoles.innerHTML = "";
    if (!roles.length) listaRoles.appendChild(el("span", { className: "ajustes-ayuda", textContent: "Sin roles asignados." }));
    roles.forEach(r => listaRoles.appendChild(el("span", { className: "chip chip-turquesa" }, [
      `${r.rol}${r.departamento_id ? ` · ${r.departamento_id}` : ""}${r.titulo ? ` · ${r.titulo}` : ""} `,
      el("button", {
        className: "chip-quitar", "aria-label": "Quitar rol", textContent: "✕",
        onclick: async () => {
          try {
            await api.asignarRol(u.id, r.rol, r.departamento_id, null, false);
            u.roles = u.roles.filter(x => x !== r);
            pintarRoles(u.roles);
            mostrarToast("Rol retirado.", "exito");
          } catch (e) { mostrarToast(e.message, "error"); }
        }
      })
    ])));
  };
  pintarRoles(u.roles || []);
  const nuevoRol = select(ROLES, "voluntario");
  const rolDepto = select([["", "Sin departamento / nacional"], ...ctx.departamentos.map(d => [d.id, d.nombre])], u.departamento_id);
  const rolTitulo = input({ placeholder: "Título del rol (opcional)" });
  const btnRol = el("button", {
    type: "button", className: "btn btn-secundario btn-sm", textContent: "Agregar rol",
    onclick: async () => {
      try {
        await api.asignarRol(u.id, nuevoRol.value, rolDepto.value || null, rolTitulo.value);
        u.roles = [...(u.roles || []), { rol: nuevoRol.value, departamento_id: rolDepto.value || null, titulo: rolTitulo.value }];
        pintarRoles(u.roles);
        mostrarToast("Rol asignado.", "exito");
      } catch (e) { mostrarToast(e.message, "error"); }
    }
  });

  const cuerpo = el("div", { className: "admin-form" }, [
    el("div", { className: "admin-form-grid" }, [
      campo("Nombre completo", nombre), campo("Etiqueta visible junto a la insignia", etiqueta),
      campo("Ocupación", ocupacion), campo("Teléfono (privado)", telefono),
      campo("Estado de la cuenta", estado), campo("Departamento", depto),
      campo("Insignia", insignia),
      campo("Puede ayudar en", areaApoyo), campoAreaOtro
    ]),
    campo("Biografía", bio),
    el("div", { className: "ajustes-dato" }, [el("span", { textContent: "Correo" }), el("strong", { textContent: u.correo || "—" })]),
    el("div", { className: "ajustes-dato" }, [el("span", { textContent: "Registro · último ingreso" }), el("strong", { textContent: `${fecha(u.created_at)} · ${fecha(u.ultimo_ingreso, true)}` })]),
    el("h4", { style: "margin-top: 1rem;", textContent: "Roles" }),
    listaRoles,
    el("div", { className: "admin-form-grid" }, [campo("Nuevo rol", nuevoRol), campo("Territorio del rol", rolDepto), campo("Título", rolTitulo)]),
    btnRol,
    campo("Notas internas", notas)
  ]);

  abrirModal({
    titulo: `@${u.username}`,
    contenidoNodo: cuerpo,
    acciones: [
      { texto: "Cerrar", tipo: "secundario" },
      {
        texto: "Guardar cambios", tipo: "primario",
        onClick: async (cerrar) => {
          try {
            await api.actualizarUsuario(u.id, {
              nombre: nombre.value, cargo_titulo: etiqueta.value, bio: bio.value, ocupacion: ocupacion.value,
              telefono: telefono.value, estado: estado.value, notas_admin: notas.value,
              area_apoyo: areaApoyo.value, area_apoyo_otro: areaOtro.value,
              ...(ctx.permisos.es_admin_nacional ? { departamento_id: depto.value || null } : {})
            });
            if (insignia.value !== u.insignia) await api.otorgarInsignia(u.id, insignia.value);
            mostrarToast("Usuario actualizado.", "exito");
            cerrar();
            recargar();
          } catch (e) { mostrarToast(e.message, "error"); }
        }
      }
    ]
  });
}

// ===========================================================================
// PUBLICACIONES Y COMENTARIOS
// ===========================================================================
export async function montarPublicaciones(cont, ctx) {
  cont.innerHTML = "";
  const estado = select([["", "Todas"], ["aprobado", "Aprobadas"], ["pendiente", "Pendientes"], ["rechazado", "Rechazadas"], ["eliminada", "Eliminadas"]]);
  const busqueda = input({ type: "search", placeholder: "Buscar texto o @usuario..." });
  const lista = el("div", { className: "admin-lista" });
  cont.append(barra(estado, busqueda), lista);

  let t;
  const cargar = async () => {
    lista.innerHTML = "<div class='esqueleto' style='height: 140px;'></div>";
    try {
      const pubs = await api.listarPublicacionesAdmin(estado.value, ctx.depto(), busqueda.value.trim());
      lista.innerHTML = "";
      if (!pubs.length) return lista.appendChild(vacio("No hay publicaciones con esos filtros."));
      pubs.forEach(p => lista.appendChild(tarjetaPublicacionAdmin(p, cargar)));
    } catch (e) { error(lista, e); }
  };
  estado.addEventListener("change", cargar);
  busqueda.addEventListener("input", () => { clearTimeout(t); t = setTimeout(cargar, 350); });
  cargar();
}

export function tarjetaPublicacionAdmin(p, recargar) {
  const media = el("div", { className: "admin-media" });
  (p.media || []).forEach(m => {
    const nodo = m.tipo === "video" ? el("video", { controls: true, preload: "metadata" })
      : m.tipo === "audio" ? el("audio", { controls: true, preload: "none" })
      : el("img", { alt: "Adjunto", loading: "lazy" });
    obtenerUrlMedia(m).then(url => { if (url) nodo.src = url; });
    media.appendChild(nodo);
  });
  const estadoChip = p.eliminado_en ? ["eliminada", "chip-peligro"] : p.estado === "aprobado" ? ["aprobada", "chip-turquesa"] : [p.estado, "chip-ambar"];
  const zonaComentarios = el("div", { className: "admin-comentarios" });

  const tarjeta = el("div", { className: "aprobacion-tarjeta" }, [
    el("div", { className: "aprobacion-cabecera" }, [
      el("div", {}, [
        el("strong", { textContent: p.autor_nombre }), " ", el("span", { className: "pub-username", textContent: `@${p.autor_username}` }), " ",
        renderizarInsignia(p.autor_insignia),
        p.autor_cargo ? el("span", { className: "etiqueta-cargo", textContent: p.autor_cargo }) : null,
        el("div", { style: "font-size: 0.75rem; color: var(--texto-suave);", textContent: `${p.departamento || "Nacional"} · ${p.categoria} · ${p.visibilidad} · ${fecha(p.created_at, true)}` })
      ]),
      el("span", { className: `chip ${estadoChip[1]}`, textContent: estadoChip[0] })
    ]),
    el("p", { style: "white-space: pre-wrap; margin: 0.5rem 0;", textContent: p.contenido }),
    media,
    el("div", { style: "font-size: 0.8rem; color: var(--texto-suave);", textContent: `❤️ ${p.me_gusta_n} · 💬 ${p.comentarios_n}${p.motivo_revision ? ` · Motivo: ${p.motivo_revision}` : ""}` }),
    el("div", { className: "aprobacion-acciones" }, [
      el("button", {
        className: "btn btn-secundario btn-sm", textContent: `Ver comentarios (${p.comentarios_n})`,
        onclick: () => cargarComentariosAdmin(p.id, zonaComentarios)
      }),
      p.estado === "pendiente" && !p.eliminado_en ? el("button", {
        className: "btn btn-secundario btn-sm", textContent: "Rechazar",
        onclick: async () => {
          const motivo = prompt("Motivo del rechazo (lo verá el autor):");
          if (motivo === null) return;
          try { await api.revisarPublicacion(p.id, "rechazado", motivo); mostrarToast("Publicación rechazada.", "exito"); recargar(); } catch (e) { mostrarToast(e.message, "error"); }
        }
      }) : null,
      p.estado === "pendiente" && !p.eliminado_en ? el("button", {
        className: "btn btn-primario btn-sm", textContent: "Aprobar",
        onclick: async () => { try { await api.revisarPublicacion(p.id, "aprobado"); mostrarToast("Publicación aprobada.", "exito"); recargar(); } catch (e) { mostrarToast(e.message, "error"); } }
      }) : null,
      !p.eliminado_en ? el("button", {
        className: "btn btn-peligro btn-sm", textContent: "Eliminar",
        onclick: async () => {
          if (!confirm("¿Eliminar esta publicación? Dejará de verse en la red.")) return;
          try { await api.eliminarPublicacionAdmin(p.id); mostrarToast("Publicación eliminada.", "exito"); recargar(); } catch (e) { mostrarToast(e.message, "error"); }
        }
      }) : null
    ]),
    zonaComentarios
  ]);
  return tarjeta;
}

async function cargarComentariosAdmin(pubId, zona) {
  zona.innerHTML = "<p class='comentarios-estado'>Cargando comentarios...</p>";
  try {
    const comentarios = await api.listarComentariosAdmin(pubId);
    zona.innerHTML = "";
    if (!comentarios.length) return zona.appendChild(el("p", { className: "comentarios-estado", textContent: "Sin comentarios." }));
    comentarios.forEach(c => {
      const fila = el("div", { className: `admin-comentario ${c.estado !== "visible" ? "oculto" : ""}` }, [
        el("div", {}, [
          el("strong", { textContent: c.autor_nombre }), " ",
          el("span", { className: "pub-username", textContent: `@${c.autor_username} · ${fecha(c.created_at, true)}` }),
          c.estado !== "visible" ? el("span", { className: "chip chip-ambar", style: "margin-left: 0.35rem;", textContent: c.estado }) : null,
          el("p", { textContent: c.contenido })
        ]),
        el("button", {
          className: "btn btn-fantasma btn-sm",
          textContent: c.estado === "visible" ? "Ocultar" : "Mostrar",
          onclick: async () => {
            try { await api.moderarComentario(c.id, c.estado === "visible" ? "oculto" : "visible"); cargarComentariosAdmin(pubId, zona); }
            catch (e) { mostrarToast(e.message, "error"); }
          }
        })
      ]);
      zona.appendChild(fila);
    });
  } catch (e) { error(zona, e); }
}

// ===========================================================================
// EVENTOS
// ===========================================================================
export async function montarEventos(cont, ctx) {
  cont.innerHTML = "";
  const lista = el("div", { className: "admin-lista" });
  cont.append(barra(el("button", { className: "btn btn-primario", textContent: "➕ Crear evento", onclick: () => editarEvento(null, ctx, cargar) })), lista);

  async function cargar() {
    lista.innerHTML = "<div class='esqueleto' style='height: 120px;'></div>";
    try {
      const eventos = await api.listarEventosAdmin();
      lista.innerHTML = "";
      if (!eventos.length) return lista.appendChild(vacio("Aún no hay eventos. Crea el primero."));
      eventos.forEach(ev => {
        const depto = ctx.departamentos.find(d => d.id === ev.departamento_id)?.nombre || "Nacional";
        lista.appendChild(el("div", { className: "aprobacion-tarjeta" }, [
          el("div", { className: "aprobacion-cabecera" }, [
            el("div", {}, [
              el("strong", { textContent: ev.titulo }),
              el("div", { style: "font-size: 0.8rem; color: var(--texto-suave);", textContent: `${fecha(ev.inicio, true)} · ${ev.modalidad} · ${depto}${ev.lugar ? ` · ${ev.lugar}` : ""}` })
            ]),
            el("span", { className: `chip ${ev.estado === "aprobado" ? "chip-turquesa" : "chip-ambar"}`, textContent: ev.estado })
          ]),
          el("p", { style: "font-size: 0.9rem; white-space: pre-wrap;", textContent: ev.descripcion }),
          el("div", { className: "aprobacion-acciones" }, [
            ev.estado === "pendiente" ? el("button", { className: "btn btn-primario btn-sm", textContent: "Aprobar", onclick: () => accion(ev.id, "aprobado") }) : null,
            el("button", { className: "btn btn-secundario btn-sm", textContent: "Editar", onclick: () => editarEvento(ev, ctx, cargar) }),
            el("button", { className: "btn btn-peligro btn-sm", textContent: "Eliminar", onclick: () => confirm("¿Eliminar este evento?") && accion(ev.id, "eliminar") })
          ])
        ]));
      });
    } catch (e) { error(lista, e); }
  }
  async function accion(id, acc) {
    try { await api.resolverEvento(id, acc); mostrarToast("Evento actualizado.", "exito"); cargar(); }
    catch (e) { mostrarToast(e.message, "error"); }
  }
  cargar();
}

function editarEvento(ev, ctx, recargar) {
  const titulo = input({ maxlength: "140" }, ev?.titulo);
  const descripcion = textarea(ev?.descripcion, { rows: 4 });
  const tipo = select([["reunion", "Reunión"], ["foro", "Foro"], ["capacitacion", "Capacitación"], ["voluntariado", "Voluntariado"], ["virtual", "Virtual"]], ev?.tipo || "reunion");
  const modalidad = select([["presencial", "Presencial"], ["virtual", "Virtual"], ["mixta", "Mixta"]], ev?.modalidad || "presencial");
  const inicio = input({ type: "datetime-local" }, aLocal(ev?.inicio));
  const fin = input({ type: "datetime-local" }, aLocal(ev?.fin));
  const lugar = input({ placeholder: "Ej. Biblioteca Virgilio Barco" }, ev?.lugar);
  const direccion = input({}, ev?.direccion);
  const url = input({ type: "url", placeholder: "https://meet.google.com/..." }, ev?.url_virtual);
  const cupo = input({ type: "number", min: "1" }, ev?.cupo);
  const visibilidad = select([["publica", "Pública"], ["miembros", "Solo miembros"]], ev?.visibilidad || "publica");
  const depto = select([["", "Nacional"], ...ctx.departamentos.map(d => [d.id, d.nombre])], ev?.departamento_id || ctx.depto() || "");
  const imagen = el("input", { type: "file", accept: "image/*", className: "campo-input" });

  abrirModal({
    titulo: ev ? "Editar evento" : "Crear evento",
    contenidoNodo: el("div", { className: "admin-form" }, [
      campo("Título", titulo), campo("Descripción", descripcion),
      el("div", { className: "admin-form-grid" }, [
        campo("Tipo", tipo), campo("Modalidad", modalidad), campo("Inicio", inicio), campo("Fin", fin),
        campo("Lugar", lugar), campo("Dirección", direccion), campo("Enlace virtual", url), campo("Cupo", cupo),
        campo("Visibilidad", visibilidad), campo("Territorio", depto)
      ]),
      campo("Imagen (se convierte a WebP)", imagen)
    ]),
    acciones: [
      { texto: "Cancelar", tipo: "secundario" },
      {
        texto: "Guardar evento", tipo: "primario",
        onClick: async (cerrar) => {
          if (!titulo.value.trim() || !inicio.value) return mostrarToast("Título y fecha de inicio son obligatorios.", "alerta");
          try {
            let imagen_path = ev?.imagen_path || null;
            if (imagen.files[0]) {
              const m = await subirMediaSitio(imagen.files[0], "eventos");
              imagen_path = supabase.storage.from("sitio").getPublicUrl(m.path).data.publicUrl;
            }
            await api.guardarEvento(ev?.id, {
              titulo: titulo.value, descripcion: descripcion.value, tipo: tipo.value, modalidad: modalidad.value,
              inicio: new Date(inicio.value).toISOString(), fin: fin.value ? new Date(fin.value).toISOString() : "",
              lugar: lugar.value, direccion: direccion.value, url_virtual: url.value, cupo: cupo.value,
              visibilidad: visibilidad.value, departamento_id: depto.value, imagen_path
            });
            mostrarToast("Evento guardado y publicado.", "exito");
            cerrar();
            recargar();
          } catch (e) { mostrarToast(e.message, "error"); }
        }
      }
    ]
  });
}

// ===========================================================================
// ANUNCIOS: COMUNICADOS, ENCUESTAS Y VOTACIONES
// ===========================================================================
export async function montarAnuncios(cont, ctx) {
  cont.innerHTML = "";
  const lista = el("div", { className: "admin-lista" });
  cont.append(
    el("p", { className: "ajustes-ayuda", textContent: "Los anuncios aparecen en un modal cuando los usuarios entran a la red. Si marcas \"obligatorio\", deben responder antes de continuar." }),
    barra(
      el("button", { className: "btn btn-primario", textContent: "📢 Nuevo comunicado", onclick: () => editarAnuncio({ tipo: "comunicado" }, ctx, cargar) }),
      el("button", { className: "btn btn-secundario", textContent: "📊 Nueva encuesta", onclick: () => editarAnuncio({ tipo: "encuesta" }, ctx, cargar) }),
      el("button", { className: "btn btn-secundario", textContent: "🗳️ Nueva votación", onclick: () => editarAnuncio({ tipo: "votacion" }, ctx, cargar) })
    ),
    lista
  );

  async function cargar() {
    lista.innerHTML = "<div class='esqueleto' style='height: 120px;'></div>";
    try {
      const anuncios = await api.listarAnunciosAdmin();
      lista.innerHTML = "";
      if (!anuncios.length) return lista.appendChild(vacio("No hay anuncios todavía."));
      anuncios.forEach(a => {
        const zonaRes = el("div");
        const vigente = a.activo && (!a.termina_en || new Date(a.termina_en) > new Date());
        lista.appendChild(el("div", { className: "aprobacion-tarjeta" }, [
          el("div", { className: "aprobacion-cabecera" }, [
            el("div", {}, [
              el("strong", { textContent: a.titulo }),
              el("div", { style: "font-size: 0.8rem; color: var(--texto-suave);", textContent: `${a.tipo}${a.obligatorio ? " · obligatorio" : ""} · ${a.departamento_id ? ctx.departamentos.find(d => d.id === a.departamento_id)?.nombre : "Nacional"} · ${a.respuestas} respuestas · ${fecha(a.created_at)}` })
            ]),
            el("span", { className: `chip ${vigente ? "chip-turquesa" : "chip-ambar"}`, textContent: vigente ? "activo" : "inactivo" })
          ]),
          a.cuerpo ? el("p", { style: "white-space: pre-wrap; font-size: 0.9rem;", textContent: a.cuerpo }) : null,
          renderizarMediaAnuncio(a.media),
          el("div", { className: "aprobacion-acciones" }, [
            a.tipo !== "comunicado" ? el("button", {
              className: "btn btn-secundario btn-sm", textContent: "Ver resultados",
              onclick: async () => {
                try {
                  const res = await api.resultadosAnuncio(a.id);
                  zonaRes.innerHTML = "";
                  zonaRes.appendChild(renderizarResultados(res));
                  (res.comentarios || []).slice(0, 20).forEach(c => zonaRes.appendChild(el("p", { className: "admin-comentario", textContent: `“${c}”` })));
                } catch (e) { mostrarToast(e.message, "error"); }
              }
            }) : null,
            el("button", { className: "btn btn-secundario btn-sm", textContent: "Editar", onclick: () => editarAnuncio(a, ctx, cargar) }),
            el("button", {
              className: "btn btn-secundario btn-sm", textContent: a.activo ? "Desactivar" : "Activar",
              onclick: async () => { try { await api.guardarAnuncio(a.id, { ...a, activo: !a.activo }); cargar(); } catch (e) { mostrarToast(e.message, "error"); } }
            }),
            el("button", {
              className: "btn btn-peligro btn-sm", textContent: "Eliminar",
              onclick: async () => { if (!confirm("¿Eliminar este anuncio y sus respuestas?")) return; try { await api.eliminarAnuncio(a.id); cargar(); } catch (e) { mostrarToast(e.message, "error"); } }
            })
          ]),
          zonaRes
        ]));
      });
    } catch (e) { error(lista, e); }
  }
  cargar();
}

function editarAnuncio(a, ctx, recargar) {
  const esConsulta = a.tipo === "encuesta" || a.tipo === "votacion";
  const tipo = select([["comunicado", "Comunicado"], ["encuesta", "Encuesta"], ["votacion", "Votación"]], a.tipo);
  const titulo = input({ maxlength: "160" }, a.titulo);
  const cuerpo = textarea(a.cuerpo, { rows: 4, placeholder: "Texto del anuncio o pregunta de la encuesta" });
  const depto = select([["", "Nacional (todos)"], ...ctx.departamentos.map(d => [d.id, d.nombre])], a.departamento_id || "");
  const obligatorio = el("input", { type: "checkbox" }); obligatorio.checked = Boolean(a.obligatorio);
  const multiple = el("input", { type: "checkbox" }); multiple.checked = Boolean(a.multiple);
  const comentario = el("input", { type: "checkbox" }); comentario.checked = Boolean(a.permite_comentario);
  const mostrarRes = el("input", { type: "checkbox" }); mostrarRes.checked = a.mostrar_resultados !== false;
  const termina = input({ type: "datetime-local" }, aLocal(a.termina_en));
  const opcionesArea = textarea((a.opciones || []).map(o => o.texto).join("\n"), { rows: 4, placeholder: "Una opción por línea" });
  const archivos = el("input", { type: "file", accept: "image/*,video/mp4,video/webm,audio/*", multiple: true, className: "campo-input" });
  let media = [...(a.media || [])];
  const vistaMedia = el("div", { className: "admin-media" });
  const pintarMedia = () => {
    vistaMedia.innerHTML = "";
    media.forEach((m, i) => {
      const caja = el("div", { className: "admin-media-item" }, [renderizarMediaAnuncio([m]),
        el("button", { type: "button", className: "btn btn-fantasma btn-sm", textContent: "Quitar", onclick: () => { media.splice(i, 1); pintarMedia(); } })]);
      vistaMedia.appendChild(caja);
    });
  };
  pintarMedia();
  archivos.addEventListener("change", async () => {
    for (const f of archivos.files) {
      try {
        mostrarToast(`Procesando ${f.name}...`, "exito", 1500);
        media.push(await subirMediaSitio(f, "anuncios"));
        pintarMedia();
      } catch (e) { mostrarToast(`${f.name}: ${e.message}`, "error"); }
    }
    archivos.value = "";
  });

  const bloqueConsulta = el("div", { className: "admin-form" }, [
    campo("Opciones (una por línea)", opcionesArea),
    el("label", { className: "admin-check" }, [multiple, " Permitir varias respuestas (solo encuestas)"]),
    el("label", { className: "admin-check" }, [comentario, " Permitir comentario"]),
    el("label", { className: "admin-check" }, [mostrarRes, " Mostrar resultados a quien responde"])
  ]);
  bloqueConsulta.style.display = esConsulta ? "" : "none";
  tipo.addEventListener("change", () => { bloqueConsulta.style.display = tipo.value === "comunicado" ? "none" : ""; });

  abrirModal({
    titulo: a.id ? "Editar anuncio" : "Nuevo anuncio",
    contenidoNodo: el("div", { className: "admin-form" }, [
      el("div", { className: "admin-form-grid" }, [campo("Tipo", tipo), campo("Audiencia", depto)]),
      campo("Título", titulo), campo("Texto", cuerpo),
      bloqueConsulta,
      el("label", { className: "admin-check" }, [obligatorio, " Obligatorio: el usuario debe responder/confirmar para continuar"]),
      campo("Visible hasta (opcional)", termina),
      campo("Imágenes, video o audio (se optimizan a WebP / Opus)", archivos),
      vistaMedia
    ]),
    acciones: [
      { texto: "Cancelar", tipo: "secundario" },
      {
        texto: "Publicar", tipo: "primario",
        onClick: async (cerrar) => {
          const opciones = opcionesArea.value.split("\n").map(x => x.trim()).filter(Boolean).map(texto => ({ texto }));
          try {
            await api.guardarAnuncio(a.id, {
              tipo: tipo.value, titulo: titulo.value, cuerpo: cuerpo.value, departamento_id: depto.value,
              opciones: tipo.value === "comunicado" ? [] : opciones, multiple: multiple.checked,
              permite_comentario: comentario.checked, mostrar_resultados: mostrarRes.checked,
              obligatorio: obligatorio.checked, media, activo: a.activo !== false,
              termina_en: termina.value ? new Date(termina.value).toISOString() : ""
            });
            mostrarToast("Anuncio publicado.", "exito");
            cerrar();
            recargar();
          } catch (e) { mostrarToast(e.message, "error"); }
        }
      }
    ]
  });
}

// ===========================================================================
// GRUPOS
// ===========================================================================
export async function montarGrupos(cont, ctx) {
  cont.innerHTML = "";
  const lista = el("div", { className: "admin-lista" });
  cont.append(barra(el("button", { className: "btn btn-primario", textContent: "➕ Agregar grupo", onclick: () => editarGrupo(null, ctx, cargar) })), lista);
  async function cargar() {
    lista.innerHTML = "<div class='esqueleto' style='height: 120px;'></div>";
    try {
      const grupos = await obtenerGrupos();
      lista.innerHTML = "";
      const tabla = el("table", { className: "admin-tabla" }, [el("thead", {}, [el("tr", {}, ["Nombre", "Plataforma", "Territorio", "Enlace", ""].map(h => el("th", { textContent: h })))])]);
      const tbody = el("tbody");
      grupos.forEach(g => tbody.appendChild(el("tr", {}, [
        el("td", { textContent: g.nombre }),
        el("td", { textContent: g.plataforma }),
        el("td", { textContent: g.departamento?.nombre || "Nacional" }),
        el("td", {}, [el("a", { href: g.url, target: "_blank", rel: "noopener noreferrer", textContent: g.url.replace("https://", "") })]),
        el("td", {}, [
          el("button", { className: "btn btn-secundario btn-sm", textContent: "Editar", onclick: () => editarGrupo(g, ctx, cargar) }), " ",
          el("button", { className: "btn btn-peligro btn-sm", textContent: "Eliminar", onclick: async () => {
            if (!confirm(`¿Eliminar ${g.nombre}?`)) return;
            try { await api.eliminarGrupo(g.id); cargar(); } catch (e) { mostrarToast(e.message, "error"); }
          } })
        ])
      ])));
      tabla.appendChild(tbody);
      lista.appendChild(el("div", { className: "admin-tabla-scroll" }, [tabla]));
    } catch (e) { error(lista, e); }
  }
  cargar();
}

function editarGrupo(g, ctx, recargar) {
  const nombre = input({}, g?.nombre);
  const descripcion = textarea(g?.descripcion, { maxlength: "500" });
  const plataforma = select([["whatsapp", "WhatsApp"], ["telegram", "Telegram"], ["discord", "Discord"]], g?.plataforma || "whatsapp");
  const tipo = select([["grupo", "Grupo"], ["comunidad", "Comunidad"], ["canal", "Canal"]], g?.tipo || "grupo");
  const url = input({ type: "url", placeholder: "https://chat.whatsapp.com/..." }, g?.url);
  const depto = select([["", "Nacional"], ...ctx.departamentos.map(d => [d.id, d.nombre])], g?.departamento_id || "");
  abrirModal({
    titulo: g ? "Editar grupo" : "Agregar grupo",
    contenidoNodo: el("div", { className: "admin-form" }, [
      campo("Nombre", nombre), campo("Descripción", descripcion),
      el("div", { className: "admin-form-grid" }, [campo("Plataforma", plataforma), campo("Tipo", tipo), campo("Territorio", depto)]),
      campo("Enlace de invitación", url)
    ]),
    acciones: [
      { texto: "Cancelar", tipo: "secundario" },
      {
        texto: "Guardar", tipo: "primario",
        onClick: async (cerrar) => {
          try {
            await api.guardarGrupo(g?.id, {
              nombre: nombre.value, descripcion: descripcion.value, plataforma: plataforma.value, tipo: tipo.value,
              url: url.value.trim().split("?")[0], departamento_id: depto.value, orden: g?.orden ?? 100
            });
            mostrarToast("Grupo guardado.", "exito");
            cerrar();
            recargar();
          } catch (e) { mostrarToast(e.message.includes("url_check") ? "El enlace debe ser de WhatsApp, Telegram o Discord." : e.message, "error"); }
        }
      }
    ]
  });
}
