/**
 * Hilo de Comentarios de una Publicación · Avancemos
 * Lista los comentarios visibles y permite comentar a miembros activos.
 * Regla de oro 5: todo el contenido de usuario se inserta con textContent.
 */

import { el } from "../util/texto-seguro.js";
import { renderizarAvatar, renderizarInsignia } from "./avatar.js";
import { tiempoRelativo } from "../util/fechas.js";
import { obtenerComentarios, agregarComentario } from "../servicios/publicaciones.js";
import { obtenerUsuarioActual } from "../auth.js";
import { mostrarToast } from "./toast.js";
import { CONFIG } from "../config.js";

function renderizarComentario(c) {
  const autor = c.autor || {};
  const nombre = autor.nombre || "Miembro de Avancemos";

  const cabecera = el("div", { className: "comentario-cabecera" }, [
    el("span", { className: "pub-nombre", textContent: nombre })
  ]);
  const badge = renderizarInsignia(autor.insignia);
  if (badge) cabecera.appendChild(badge);
  if (autor.cargo_titulo) cabecera.appendChild(el("span", { className: "etiqueta-cargo", textContent: autor.cargo_titulo }));
  if (autor.username) {
    cabecera.appendChild(el("a", {
      className: "pub-username",
      href: `app.html#/u/${autor.username}`,
      textContent: `@${autor.username}`
    }));
  }
  cabecera.appendChild(el("span", { className: "pub-tiempo", textContent: `· ${tiempoRelativo(c.created_at)}` }));

  return el("div", { className: "comentario-item" }, [
    renderizarAvatar({ nombre, avatar_path: autor.avatar_path }, "sm"),
    el("div", { className: "comentario-cuerpo" }, [
      cabecera,
      el("p", { className: "comentario-texto", textContent: c.contenido })
    ])
  ]);
}

/**
 * Construye el hilo de comentarios dentro de `contenedor`.
 * @param {object} pub Publicación (necesita id y autor_username)
 * @param {HTMLElement} contenedor Nodo donde se dibuja el hilo
 * @param {object} opciones { onNuevoComentario(total) }
 */
export async function montarHiloComentarios(pub, contenedor, opciones = {}) {
  contenedor.innerHTML = "";
  contenedor.classList.add("hilo-comentarios");

  const lista = el("div", { className: "comentarios-lista", "aria-live": "polite" }, [
    el("p", { className: "comentarios-estado", textContent: "Cargando comentarios..." })
  ]);
  contenedor.appendChild(lista);

  let total = 0;
  const pintarVacio = () => {
    lista.innerHTML = "";
    lista.appendChild(el("p", {
      className: "comentarios-estado",
      textContent: "Aún no hay comentarios. ¡Sé el primero en aportar!"
    }));
  };

  try {
    const comentarios = await obtenerComentarios(pub.id);
    total = comentarios.length;
    lista.innerHTML = "";
    if (!comentarios.length) pintarVacio();
    comentarios.forEach(c => lista.appendChild(renderizarComentario(c)));
  } catch (e) {
    lista.innerHTML = "";
    lista.appendChild(el("p", {
      className: "comentarios-estado",
      style: "color: var(--error);",
      textContent: "No se pudieron cargar los comentarios."
    }));
  }

  const usuario = await obtenerUsuarioActual();
  if (!usuario) {
    contenedor.appendChild(el("div", { className: "comentarios-login" }, [
      el("span", { textContent: "Ingresa con tu cuenta para comentar. " }),
      el("a", { href: "ingresar.html", textContent: "Ingresar" })
    ]));
    return;
  }

  const input = el("textarea", {
    className: "campo-textarea comentario-input",
    rows: 2,
    maxlength: String(CONFIG.LIMITES.MAX_CARACTERES_COMENTARIO),
    placeholder: `Responder a @${pub.autor_username || "autor"}...`,
    "aria-label": "Escribe tu comentario"
  });
  const btn = el("button", { className: "btn btn-primario btn-sm", type: "submit", textContent: "Comentar" });
  const form = el("form", { className: "comentario-form" }, [input, btn]);

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const texto = input.value.trim();
    if (!texto) return;
    btn.disabled = true;
    btn.textContent = "Enviando...";
    try {
      const nuevo = await agregarComentario(pub.id, texto);
      if (total === 0) lista.innerHTML = "";
      total += 1;
      lista.appendChild(renderizarComentario(nuevo));
      lista.scrollTop = lista.scrollHeight;
      input.value = "";
      if (opciones.onNuevoComentario) opciones.onNuevoComentario(total);
    } catch (err) {
      const msg = err?.code === "42501" || /row-level security/i.test(err?.message || "")
        ? "Tu cuenta aún no puede comentar (debe estar aprobada y activa)."
        : (err.message || "No se pudo publicar el comentario");
      mostrarToast(msg, "error");
    } finally {
      btn.disabled = false;
      btn.textContent = "Comentar";
    }
  });

  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) form.requestSubmit();
  });

  contenedor.appendChild(form);
}

/** Abre el hilo de comentarios en una hoja/modal. */
export function abrirComentarios(pub, opciones = {}) {
  const overlay = el("div", { className: "modal-overlay modal-hoja", role: "dialog", "aria-modal": "true", "aria-label": "Comentarios" });
  const cuerpo = el("div", {});
  const cerrarBtn = el("button", { className: "btn btn-fantasma btn-sm", "aria-label": "Cerrar", textContent: "✕" });
  const contenido = el("div", { className: "modal-contenido" }, [
    el("div", { className: "modal-cabecera" }, [
      el("h3", { textContent: "Comentarios", style: "font-size: var(--fs-lg);" }),
      cerrarBtn
    ]),
    el("div", { className: "comentario-original" }, [
      el("strong", { textContent: pub.autor_nombre || "" }),
      el("p", { textContent: (pub.contenido || "").slice(0, 280) + ((pub.contenido || "").length > 280 ? "…" : "") })
    ]),
    cuerpo
  ]);
  overlay.appendChild(contenido);
  document.body.appendChild(overlay);
  document.body.classList.add("sin-scroll");

  const cerrar = () => {
    overlay.classList.remove("abierto");
    document.body.classList.remove("sin-scroll");
    document.removeEventListener("keydown", onKey);
    setTimeout(() => overlay.remove(), 220);
  };
  const onKey = (e) => { if (e.key === "Escape") cerrar(); };
  cerrarBtn.onclick = cerrar;
  overlay.addEventListener("click", (e) => { if (e.target === overlay) cerrar(); });
  document.addEventListener("keydown", onKey);
  requestAnimationFrame(() => overlay.classList.add("abierto"));

  montarHiloComentarios(pub, cuerpo, opciones);
  return { cerrar };
}
