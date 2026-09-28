/**
 * Componente de Avatar e Insignias Estilo X · Avancemos
 */

import { el } from "../util/texto-seguro.js";

export function renderizarInsignia(tipo) {
  if (!tipo || tipo === "ninguna") return null;

  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("width", "17");
  svg.setAttribute("height", "17");
  svg.setAttribute("fill", "currentColor");
  svg.classList.add("insignia-badge", `insignia-${tipo}`);

  let titulo = "Identidad Verificada";
  if (tipo === "dorada") titulo = "Vocería Oficial · Avancemos";
  if (tipo === "gris") titulo = "Servidor Público · Elección Popular";

  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  // Ícono de insignia verificada tipo chulito en círculo estilizado
  path.setAttribute(
    "d",
    "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"
  );
  svg.appendChild(path);

  const enlace = el("a", {
    href: "insignias.html",
    title: titulo,
    "aria-label": titulo,
    style: "display: inline-flex; align-items: center; text-decoration: none;"
  }, [svg]);

  return enlace;
}

export function renderizarAvatar(perfil, tamano = "md") {
  const cont = el("div", { className: "avatar-contenedor" });

  if (perfil?.avatar_path) {
    const img = el("img", {
      src: perfil.avatar_path,
      alt: perfil.nombre || "Avatar",
      className: `avatar avatar-${tamano}`,
      loading: "lazy"
    });
    img.onerror = () => {
      img.src = "assets/avatar-default.svg";
    };
    cont.appendChild(img);
  } else {
    const inicial = (perfil?.nombre || "A").charAt(0).toUpperCase();
    const div = el("div", {
      className: `avatar avatar-${tamano}`,
      style: "display: flex; align-items: center; justify-content: center; font-weight: 700; color: var(--azul-noche); background: var(--marfil); font-family: var(--fuente-titulo);"
    }, [inicial]);
    cont.appendChild(div);
  }

  return cont;
}
