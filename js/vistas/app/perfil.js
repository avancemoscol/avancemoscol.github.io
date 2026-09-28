/**
 * Vista de Perfil (propio y de otros) · Avancemos
 * - Otros usuarios solo ven el primer nombre.
 * - Pestañas: Publicaciones, Seguidores y Siguiendo.
 * - En el perfil propio: editar biografía y editar/eliminar publicaciones.
 */

import { el } from "../../util/texto-seguro.js";
import { renderizarAvatar, renderizarInsignia } from "../../ui/avatar.js";
import { renderizarTarjetaPublicacion } from "../../ui/tarjeta-publicacion.js";
import { mostrarToast } from "../../ui/toast.js";
import { abrirModal } from "../../ui/modal.js";
import { supabase } from "../../supabase.js";
import {
  obtenerPerfilPorUsername, seguirUsuario, dejarDeSeguir, obtenerRelaciones, actualizarBio
} from "../../servicios/perfiles.js";
import { obtenerPublicacionesDePerfil, editarPublicacion, eliminarPublicacion } from "../../servicios/publicaciones.js";
import { iniciarConversacion } from "../../servicios/mensajes.js";
import { solicitarInsignia } from "../../servicios/verificacion.js";

async function siguiendoA(miId, otroId) {
  const { data } = await supabase.from("seguidores").select("seguido_id")
    .eq("seguidor_id", miId).eq("seguido_id", otroId).maybeSingle();
  return Boolean(data);
}

function botonSeguir(perfilId, username, siguiendoInicial, onCambio) {
  let siguiendo = siguiendoInicial;
  const btn = el("button", { className: "btn btn-sm" });
  const pintar = () => {
    btn.textContent = siguiendo ? "Siguiendo" : "Seguir";
    btn.className = siguiendo ? "btn btn-secundario btn-sm" : "btn btn-primario btn-sm";
    btn.setAttribute("aria-pressed", String(siguiendo));
  };
  pintar();
  btn.onclick = async (e) => {
    e.stopPropagation();
    btn.disabled = true;
    try {
      if (siguiendo) await dejarDeSeguir(perfilId); else await seguirUsuario(perfilId);
      siguiendo = !siguiendo;
      pintar();
      mostrarToast(siguiendo ? `Ahora sigues a @${username}` : `Dejaste de seguir a @${username}`, "exito");
      if (onCambio) onCambio(siguiendo);
    } catch (err) {
      mostrarToast(err.message || "No se pudo actualizar", "error");
    } finally {
      btn.disabled = false;
    }
  };
  return btn;
}

function filaPersona(persona, miUsuario) {
  const fila = el("div", { className: "persona-fila" }, [
    renderizarAvatar({ nombre: persona.nombre, avatar_path: persona.avatar_path }, "md"),
    el("a", { className: "persona-datos", href: `#/u/${persona.username}` }, [
      el("div", { className: "persona-nombre" }, [
        el("strong", { textContent: persona.nombre }),
        renderizarInsignia(persona.insignia),
        persona.cargo_titulo ? el("span", { className: "etiqueta-cargo", textContent: persona.cargo_titulo }) : null
      ]),
      el("span", { className: "pub-username", textContent: `@${persona.username}` })
    ])
  ]);
  if (miUsuario && persona.id !== miUsuario.id) {
    fila.appendChild(botonSeguir(persona.id, persona.username, persona.lo_sigo));
  }
  return fila;
}

function abrirEditorPublicacion(pub, nodoTexto, onGuardado) {
  const area = el("textarea", { className: "campo-textarea", rows: 6, maxlength: "3000" });
  area.value = pub.contenido;
  const aviso = el("p", {
    style: "font-size: var(--fs-xs); color: var(--texto-suave); margin-top: 0.5rem;",
    textContent: "Al guardar, la publicación vuelve a revisión del equipo departamental antes de mostrarse de nuevo."
  });
  abrirModal({
    titulo: "Editar publicación",
    contenidoNodo: el("div", {}, [area, aviso]),
    acciones: [
      { texto: "Cancelar", tipo: "secundario" },
      {
        texto: "Guardar cambios", tipo: "primario",
        onClick: async (cerrar) => {
          const nuevo = area.value.trim();
          if (!nuevo) return mostrarToast("La publicación no puede quedar vacía.", "alerta");
          try {
            const estado = await editarPublicacion(pub.id, nuevo);
            pub.contenido = nuevo;
            if (nodoTexto) nodoTexto.textContent = nuevo;
            mostrarToast(estado === "pendiente" ? "Cambios guardados. Tu publicación está en revisión." : "Cambios guardados.", "exito");
            cerrar();
            if (onGuardado) onGuardado();
          } catch (err) {
            mostrarToast(err.message || "No se pudo editar", "error");
          }
        }
      }
    ]
  });
}

function confirmarEliminar(pub, tarjeta) {
  abrirModal({
    titulo: "Eliminar publicación",
    contenidoNodo: el("p", { textContent: "¿Seguro que quieres eliminar esta publicación? Dejará de verse en la red." }),
    acciones: [
      { texto: "Cancelar", tipo: "secundario" },
      {
        texto: "Eliminar", tipo: "peligro",
        onClick: async (cerrar) => {
          try {
            await eliminarPublicacion(pub.id);
            tarjeta.remove();
            mostrarToast("Publicación eliminada.", "exito");
            cerrar();
          } catch (err) {
            mostrarToast(err.message || "No se pudo eliminar", "error");
          }
        }
      }
    ]
  });
}

export async function montarPerfil(cont, username, miUsuario, pestanaInicial = "publicaciones") {
  cont.innerHTML = "";
  cont.appendChild(el("div", { className: "esqueleto", style: "padding: 2rem;", textContent: "Cargando perfil..." }));

  let p = null;
  try { p = await obtenerPerfilPorUsername(username); } catch (_) { p = null; }
  if (!p) {
    cont.innerHTML = "";
    cont.appendChild(el("div", { style: "padding: 2rem;", textContent: "Perfil no encontrado." }));
    return;
  }

  const esPropio = Boolean(miUsuario && miUsuario.id === p.id);
  // El nombre completo solo lo ve su dueño
  const nombreVisible = esPropio ? miUsuario.nombre : p.nombre;

  cont.innerHTML = "";
  const portada = el("div", { className: "perfil-portada" });
  const acciones = el("div", { className: "perfil-acciones" });
  const cabecera = el("div", { className: "perfil-cabecera" }, [
    el("div", { className: "perfil-fila-superior" }, [renderizarAvatar({ nombre: nombreVisible, avatar_path: p.avatar_path }, "xl"), acciones]),
    el("div", { className: "perfil-nombre" }, [
      el("h3", { textContent: nombreVisible }),
      renderizarInsignia(p.insignia),
      p.cargo_titulo ? el("span", { className: "etiqueta-cargo", textContent: p.cargo_titulo }) : null
    ]),
    el("div", { className: "pub-username", textContent: `@${p.username}` }),
    el("p", { className: "perfil-bio", textContent: p.bio || (esPropio ? "Aún no tienes biografía. Agrégala en Ajustes." : "Sin biografía aún.") })
  ]);

  const contSeguidores = el("strong", { textContent: String(p.seguidores_n || 0) });
  const stats = el("div", { className: "perfil-stats" }, [
    el("button", { className: "perfil-stat", onclick: () => cambiar("siguiendo") }, [el("strong", { textContent: String(p.siguiendo_n || 0) }), " Siguiendo"]),
    el("button", { className: "perfil-stat", onclick: () => cambiar("seguidores") }, [contSeguidores, " Seguidores"]),
    el("span", { className: "perfil-stat" }, [el("strong", { textContent: String(p.publicaciones_n || 0) }), " Publicaciones"])
  ]);
  cabecera.appendChild(stats);

  if (esPropio) {
    acciones.appendChild(el("a", { href: "#/ajustes", className: "btn btn-secundario btn-sm", textContent: "Editar biografía" }));
  } else if (miUsuario) {
    const loSigo = await siguiendoA(miUsuario.id, p.id);
    const btnMensaje = el("button", { className: "btn btn-secundario btn-sm", textContent: "Mensaje" });
    const actualizarMensaje = (sigo) => {
      btnMensaje.disabled = !sigo;
      btnMensaje.title = sigo ? "Enviar mensaje directo" : "Sigue a esta persona para poder enviarle mensajes";
    };
    actualizarMensaje(loSigo);
    btnMensaje.onclick = async () => {
      try {
        const convId = await iniciarConversacion(p.id);
        window.location.hash = `#/mensajes/${convId}`;
      } catch (err) {
        mostrarToast(err.message || "No se pudo abrir la conversación", "error");
      }
    };
    acciones.append(btnMensaje, botonSeguir(p.id, p.username, loSigo, (sigo) => {
      actualizarMensaje(sigo);
      contSeguidores.textContent = String((parseInt(contSeguidores.textContent, 10) || 0) + (sigo ? 1 : -1));
    }));
  } else {
    acciones.appendChild(el("a", { href: "ingresar.html", className: "btn btn-primario btn-sm", textContent: "Ingresa para seguir" }));
  }

  const pestanas = el("div", { className: "pestanas perfil-pestanas", role: "tablist" });
  const cuerpo = el("div", { className: "perfil-cuerpo" });
  const tabs = [["publicaciones", esPropio ? "Mis publicaciones" : "Publicaciones"], ["seguidores", "Seguidores"], ["siguiendo", "Siguiendo"]];
  tabs.forEach(([id, texto]) => {
    pestanas.appendChild(el("button", { className: "pestana", role: "tab", "data-tab": id, textContent: texto, onclick: () => cambiar(id) }));
  });

  cont.append(portada, cabecera, pestanas, cuerpo);

  async function cambiar(tab) {
    pestanas.querySelectorAll(".pestana").forEach(b => {
      const activa = b.dataset.tab === tab;
      b.classList.toggle("activa", activa);
      b.setAttribute("aria-selected", String(activa));
    });
    cuerpo.innerHTML = "";
    cuerpo.appendChild(el("p", { className: "comentarios-estado", textContent: "Cargando..." }));

    if (tab === "publicaciones") {
      try {
        const pubs = await obtenerPublicacionesDePerfil(p.username);
        cuerpo.innerHTML = "";
        if (!pubs.length) {
          cuerpo.appendChild(el("div", { className: "estado-vacio" }, [
            el("div", { className: "estado-vacio-icono", textContent: "📝" }),
            el("p", { textContent: esPropio ? "Aún no has publicado. Toca ➕ para compartir tu primera propuesta." : "Todavía no hay publicaciones." })
          ]));
        }
        pubs.forEach(pub => cuerpo.appendChild(renderizarTarjetaPublicacion(pub, {
          esPropia: esPropio,
          onEditar: (pb, nodoTexto) => abrirEditorPublicacion(pb, nodoTexto, () => cambiar("publicaciones")),
          onEliminar: confirmarEliminar
        })));
      } catch (err) {
        cuerpo.innerHTML = "";
        cuerpo.appendChild(el("p", { style: "padding: 1.5rem; color: var(--error);", textContent: err.message }));
      }
      return;
    }

    if (!miUsuario) {
      cuerpo.innerHTML = "";
      cuerpo.appendChild(el("p", { className: "comentarios-estado", textContent: "Ingresa con tu cuenta para ver seguidores." }));
      return;
    }
    try {
      const personas = await obtenerRelaciones(p.username, tab);
      cuerpo.innerHTML = "";
      if (!personas.length) {
        cuerpo.appendChild(el("p", { className: "comentarios-estado", textContent: tab === "seguidores" ? "Aún no hay seguidores." : "Aún no sigue a nadie." }));
      }
      personas.forEach(persona => cuerpo.appendChild(filaPersona(persona, miUsuario)));
    } catch (err) {
      cuerpo.innerHTML = "";
      cuerpo.appendChild(el("p", { style: "padding: 1.5rem; color: var(--error);", textContent: err.message }));
    }
  }

  cambiar(pestanaInicial);
}

/** Vista de Ajustes: solo la biografía es editable */
export function montarAjustes(cont, miUsuario, { onSolicitarInsignia, onCerrarSesion } = {}) {
  cont.innerHTML = "";
  const bio = el("textarea", { className: "campo-textarea", rows: 4, maxlength: "280", id: "ajustes-bio", placeholder: "Cuéntale a la comunidad quién eres y qué te mueve..." });
  bio.value = miUsuario.bio || "";
  const contador = el("span", { className: "widget-contador", textContent: `${bio.value.length}/280` });
  bio.addEventListener("input", () => { contador.textContent = `${bio.value.length}/280`; });
  const btnGuardar = el("button", { className: "btn btn-primario btn-sm", textContent: "Guardar biografía" });
  btnGuardar.onclick = async () => {
    btnGuardar.disabled = true;
    try {
      await actualizarBio(bio.value);
      miUsuario.bio = bio.value.trim();
      mostrarToast("Biografía actualizada.", "exito");
    } catch (err) {
      mostrarToast(err.message || "No se pudo guardar", "error");
    } finally {
      btnGuardar.disabled = false;
    }
  };

  const estadoInsignia = el("p", { className: "ajustes-ayuda", textContent: "Solicita tu insignia cuando quieras: azul (identidad verificada), gris (cargo público) o dorada (vocería oficial)." });
  const tarjetaInsignia = el("div", { className: "tarjeta" }, [
    el("h3", { textContent: "Verificación con insignia" }),
    estadoInsignia,
    el("button", { className: "btn btn-secundario btn-sm", textContent: "Solicitar insignia", onclick: () => abrirSolicitudInsignia(pintarEstadoInsignia) })
  ]);
  async function pintarEstadoInsignia() {
    const { data } = await supabase.rpc("mi_solicitud_insignia");
    if (!data) return;
    const txt = { pendiente: "en revisión", aprobado: "aprobada", rechazado: "no aprobada" }[data.estado] || data.estado;
    estadoInsignia.textContent = `Tu última solicitud (insignia ${data.insignia_solicitada}) está ${txt}.` +
      (data.estado === "pendiente" ? " Te avisaremos por notificación." : " Puedes volver a solicitar cuando quieras.");
  }
  pintarEstadoInsignia();

  const dato = (etiqueta, valor) => el("div", { className: "ajustes-dato" }, [
    el("span", { textContent: etiqueta }), el("strong", { textContent: valor || "—" })
  ]);

  cont.appendChild(el("div", { className: "ajustes-contenedor" }, [
    el("div", { className: "tarjeta" }, [
      el("h3", { textContent: "Mi perfil" }),
      el("p", { className: "ajustes-ayuda", textContent: "Puedes editar tu biografía. Para cambiar otros datos, radica un caso en Dudas y Soporte." }),
      dato("Nombre completo", miUsuario.nombre),
      dato("Usuario", `@${miUsuario.username}`),
      dato("Departamento", miUsuario.departamento_nombre),
      dato("Municipio", miUsuario.municipio_nombre),
      miUsuario.cargo_titulo ? dato("Etiqueta", miUsuario.cargo_titulo) : null,
      el("label", { className: "campo-etiqueta", for: "ajustes-bio", style: "margin-top: 1rem; display: block;", textContent: "Biografía" }),
      bio,
      el("div", { style: "display: flex; justify-content: space-between; align-items: center; margin-top: 0.5rem;" }, [contador, btnGuardar])
    ]),
    tarjetaInsignia,
    el("div", { className: "tarjeta" }, [
      el("h3", { textContent: "Sesión" }),
      el("button", { className: "btn btn-peligro btn-sm", textContent: "Cerrar sesión", onclick: () => onCerrarSesion && onCerrarSesion() })
    ])
  ]));
}

/** Formulario de solicitud de insignia (sin límites de días) */
export function abrirSolicitudInsignia(onEnviada) {
  const tipo = el("select", { className: "campo-select" }, [
    el("option", { value: "azul", textContent: "Azul · identidad verificada" }),
    el("option", { value: "gris", textContent: "Gris · servidor público o cargo de elección" }),
    el("option", { value: "dorada", textContent: "Dorada · vocería oficial del movimiento" })
  ]);
  const cargo = el("input", { className: "campo-input", maxlength: "120", placeholder: "Ej. Líder comunal de Kennedy, concejal de Tunja..." });
  const motivo = el("textarea", { className: "campo-textarea", rows: 3, maxlength: "500", placeholder: "Cuéntanos por qué solicitas la insignia" });
  const enlaces = el("input", { className: "campo-input", placeholder: "Enlaces que respalden tu solicitud (opcional, separados por coma)" });
  const metodo = el("select", { className: "campo-select" }, [
    el("option", { value: "videollamada", textContent: "Videollamada" }),
    el("option", { value: "presencial", textContent: "Presencial" })
  ]);
  const campo = (t, c) => el("label", { className: "campo", style: "display: flex; flex-direction: column; gap: 0.25rem;" }, [el("span", { className: "campo-etiqueta", textContent: t }), c]);
  abrirModal({
    titulo: "Solicitar insignia",
    contenidoNodo: el("div", { style: "display: flex; flex-direction: column; gap: 0.75rem;" }, [
      campo("Tipo de insignia", tipo), campo("Cargo o actividad", cargo), campo("Motivo", motivo),
      campo("Enlaces", enlaces), campo("Verificación preferida", metodo),
      el("p", { className: "ajustes-ayuda", textContent: "El equipo de tu departamento revisará la solicitud. Las insignias gris y dorada las aprueba el administrador nacional." })
    ]),
    acciones: [
      { texto: "Cancelar", tipo: "secundario" },
      {
        texto: "Enviar solicitud", tipo: "primario",
        onClick: async (cerrar) => {
          if (!cargo.value.trim() || !motivo.value.trim()) return mostrarToast("Completa el cargo y el motivo.", "alerta");
          try {
            await solicitarInsignia({
              insignia: tipo.value, cargo: cargo.value.trim(), motivo: motivo.value.trim(),
              enlaces: enlaces.value.split(",").map(x => x.trim()).filter(x => /^https?:\/\//.test(x)),
              metodoPreferido: metodo.value
            });
            mostrarToast("Solicitud enviada. Te avisaremos cuando sea revisada.", "exito");
            cerrar();
            if (onEnviada) onEnviada();
          } catch (e) {
            mostrarToast(e.message || "No se pudo enviar la solicitud", "error");
          }
        }
      }
    ]
  });
}
