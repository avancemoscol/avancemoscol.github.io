/**
 * Componente Tarjeta de Publicación Estilo X · Avancemos
 * Regla de oro 5: NUNCA innerHTML con contenido de usuario. Todo construido con DOM nodes y textContent.
 */

import { el } from "../util/texto-seguro.js";
import { renderizarAvatar, renderizarInsignia } from "./avatar.js";
import { tiempoRelativo } from "../util/fechas.js";
import { darMeGusta, quitarMeGusta, guardarPublicacion, quitarGuardado, obtenerUrlMedia } from "../servicios/publicaciones.js";
import { abrirComentarios } from "./comentarios.js";
import { mostrarToast } from "./toast.js";

export function renderizarTarjetaPublicacion(pub, opciones = {}) {
  const tarjeta = el("article", {
    className: "tarjeta-pub",
    "data-id": pub.id
  });

  // Avatar columna izquierda
  const colAvatar = el("div", { style: "flex-shrink: 0;" }, [
    renderizarAvatar({ nombre: pub.autor_nombre, avatar_path: pub.autor_avatar }, "md")
  ]);

  // Contenido columna derecha
  const colContenido = el("div", { className: "pub-contenido-wrap" });

  // Cabecera: Nombre, Insignia, @usuario, Departamento, Tiempo
  const cabecera = el("div", { className: "pub-header" });
  const nombreSpan = el("span", { className: "pub-nombre", textContent: pub.autor_nombre });
  cabecera.appendChild(nombreSpan);

  if (pub.autor_insignia && pub.autor_insignia !== "ninguna") {
    const badge = renderizarInsignia(pub.autor_insignia);
    if (badge) cabecera.appendChild(badge);
  }

  if (pub.es_oficial) {
    cabecera.appendChild(el("span", { className: "chip chip-ambar", style: "font-size: 0.65rem; padding: 0.1rem 0.4rem;", textContent: "Oficial" }));
  }

  const enlaceUsuario = el("a", { className: "pub-username", href: `app.html#/u/${pub.autor_username}`, textContent: `@${pub.autor_username}` });
  enlaceUsuario.onclick = (e) => e.stopPropagation();
  cabecera.appendChild(enlaceUsuario);
  cabecera.appendChild(el("span", { style: "color: var(--texto-suave); font-size: 0.75rem;", textContent: "·" }));
  cabecera.appendChild(el("span", { className: "pub-tiempo", textContent: tiempoRelativo(pub.publicado_en) }));

  // Texto del post
  const textoP = el("p", { className: "pub-texto" });
  parsearContenidoConEnlaces(pub.contenido, textoP);

  colContenido.appendChild(cabecera);
  colContenido.appendChild(textoP);

  // Media (Imágenes / Video)
  if (pub.media && pub.media.length > 0) {
    const cant = Math.min(pub.media.length, 4);
    const grillaMedia = el("div", { className: `pub-media-grilla grilla-${cant}` });

    pub.media.slice(0, 4).forEach((m) => {
      let mediaElem;
      if (m.tipo === "video") {
        mediaElem = el("video", {
          className: "pub-media-item",
          controls: true,
          playsinline: true,
          preload: "metadata"
        });
      } else {
        mediaElem = el("img", {
          alt: m.alt_text || "Imagen adjunta",
          className: "pub-media-item",
          loading: "lazy"
        });
      }
      mediaElem.onclick = (e) => e.stopPropagation();
      // La media puede estar en un bucket privado: se resuelve con URL firmada
      obtenerUrlMedia(m).then((url) => {
        if (url) mediaElem.src = url;
        else mediaElem.replaceWith(el("div", { className: "pub-media-no-disponible", textContent: "Archivo en revisión" }));
      });
      grillaMedia.appendChild(mediaElem);
    });

    colContenido.appendChild(grillaMedia);
  }

  // Barra de Acciones (Comentar, Repost, Me gusta, Guardar, Compartir WhatsApp)
  const accionesBarra = el("div", { className: "pub-acciones" });

  // Comentar: abre el hilo con todos los comentarios
  const contadorComentarios = el("span", { textContent: pub.comentarios_n > 0 ? String(pub.comentarios_n) : "" });
  const verComentarios = () => {
    if (opciones.onComentar) return opciones.onComentar(pub);
    abrirComentarios(pub, {
      onNuevoComentario: (total) => {
        pub.comentarios_n = total;
        contadorComentarios.textContent = String(total);
        enlaceComentarios.textContent = textoEnlaceComentarios();
      }
    });
  };
  const btnComentar = el("button", {
    className: "pub-accion-btn",
    title: "Ver y escribir comentarios",
    "aria-label": "Comentarios",
    onclick: (e) => {
      e.stopPropagation();
      verComentarios();
    }
  }, [
    el("span", { textContent: "💬" }),
    contadorComentarios
  ]);
  const textoEnlaceComentarios = () => pub.comentarios_n > 0
    ? `Ver ${pub.comentarios_n === 1 ? "1 comentario" : `los ${pub.comentarios_n} comentarios`}`
    : "Comentar";
  const enlaceComentarios = el("button", {
    className: "pub-ver-comentarios",
    textContent: textoEnlaceComentarios(),
    onclick: (e) => {
      e.stopPropagation();
      verComentarios();
    }
  });

  // Me gusta
  let leGusta = Boolean(pub.le_gusta);
  let conteoMg = pub.me_gusta_n || 0;
  const contadorMgSpan = el("span", { textContent: conteoMg > 0 ? String(conteoMg) : "" });
  const btnMeGusta = el("button", {
    className: `pub-accion-btn accion-mg ${leGusta ? "mg-activo" : ""}`,
    onclick: async (e) => {
      e.stopPropagation();
      try {
        if (leGusta) {
          leGusta = false;
          conteoMg = Math.max(0, conteoMg - 1);
          btnMeGusta.classList.remove("mg-activo");
          contadorMgSpan.textContent = conteoMg > 0 ? String(conteoMg) : "";
          await quitarMeGusta(pub.id);
        } else {
          leGusta = true;
          conteoMg += 1;
          btnMeGusta.classList.add("mg-activo");
          contadorMgSpan.textContent = String(conteoMg);
          await darMeGusta(pub.id);
        }
      } catch (err) {
        mostrarToast(err.message, "error");
      }
    }
  }, [
    el("span", { textContent: "❤️" }),
    contadorMgSpan
  ]);

  // Guardar
  let guardado = Boolean(pub.guardado);
  const btnGuardar = el("button", {
    className: `pub-accion-btn ${guardado ? "guardado-activo" : ""}`,
    title: "Guardar publicación",
    "aria-label": "Guardar publicación",
    onclick: async (e) => {
      e.stopPropagation();
      try {
        if (guardado) {
          guardado = false;
          btnGuardar.classList.remove("guardado-activo");
          await quitarGuardado(pub.id);
          mostrarToast("Eliminado de guardados", "alerta");
        } else {
          guardado = true;
          btnGuardar.classList.add("guardado-activo");
          await guardarPublicacion(pub.id);
          mostrarToast("Publicación guardada", "exito");
        }
      } catch (err) {
        mostrarToast(err.message, "error");
      }
    }
  }, [
    el("span", { textContent: "🔖" })
  ]);

  // Compartir en WhatsApp (con https://wa.me/?text= según prompt)
  const btnCompartir = el("button", {
    className: "pub-accion-btn",
    title: "Compartir en WhatsApp",
    "aria-label": "Compartir en WhatsApp",
    onclick: (e) => {
      e.stopPropagation();
      const enlacePub = `${window.location.origin}/publicacion.html?id=${pub.id}`;
      const textoWa = encodeURIComponent(`Lee esta publicación en Avancemos: ${enlacePub}`);
      window.open(`https://wa.me/?text=${textoWa}`, "_blank", "noopener,noreferrer");
    }
  }, [
    el("span", { textContent: "↗️" })
  ]);

  accionesBarra.appendChild(btnComentar);
  accionesBarra.appendChild(btnMeGusta);
  accionesBarra.appendChild(btnGuardar);
  accionesBarra.appendChild(btnCompartir);

  colContenido.appendChild(accionesBarra);
  if (opciones.mostrarEnlaceComentarios !== false) colContenido.appendChild(enlaceComentarios);

  tarjeta.appendChild(colAvatar);
  tarjeta.appendChild(colContenido);

  tarjeta.onclick = (e) => {
    if (e.target.closest("a, button, video, input, textarea")) return;
    if (opciones.onClic) opciones.onClic(pub);
    else verComentarios();
  };

  return tarjeta;
}

function parsearContenidoConEnlaces(texto, contenedor) {
  if (!texto) return;
  // Expresión para links, #hashtags y @menciones
  const regex = /(https?:\/\/[^\s]+)|(#\w+)|(@\w+)/g;
  let ultimoIndice = 0;
  let match;

  while ((match = regex.exec(texto)) !== null) {
    if (match.index > ultimoIndice) {
      contenedor.appendChild(document.createTextNode(texto.slice(ultimoIndice, match.index)));
    }

    const token = match[0];
    if (token.startsWith("http")) {
      const a = el("a", {
        href: token,
        target: "_blank",
        rel: "noopener noreferrer",
        textContent: token
      });
      a.onclick = (e) => e.stopPropagation();
      contenedor.appendChild(a);
    } else if (token.startsWith("#")) {
      const tagSpan = el("a", {
        href: `app.html#/explorar?tag=${token.slice(1)}`,
        style: "color: var(--turquesa); font-weight: 600;",
        textContent: token
      });
      tagSpan.onclick = (e) => e.stopPropagation();
      contenedor.appendChild(tagSpan);
    } else if (token.startsWith("@")) {
      const userSpan = el("a", {
        href: `app.html#/u/${token.slice(1)}`,
        style: "color: var(--turquesa); font-weight: 600;",
        textContent: token
      });
      userSpan.onclick = (e) => e.stopPropagation();
      contenedor.appendChild(userSpan);
    }

    ultimoIndice = match.index + token.length;
  }

  if (ultimoIndice < texto.length) {
    contenedor.appendChild(document.createTextNode(texto.slice(ultimoIndice)));
  }
}
