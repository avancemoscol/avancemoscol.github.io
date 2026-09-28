/**
 * Componente Modal Accesible · Avancemos
 */

import { el } from "../util/texto-seguro.js";

export function abrirModal({ titulo, contenidoNodo, acciones = [] }) {
  const overlay = el("div", { className: "modal-overlay" });
  const contenido = el("div", { className: "modal-contenido" });

  const cabecera = el("div", {
    style: "display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.25rem; border-bottom: 1px solid var(--borde-suave); padding-bottom: 0.75rem;"
  }, [
    el("h3", { textContent: titulo, style: "font-size: var(--fs-lg);" }),
    el("button", {
      className: "btn btn-fantasma btn-sm",
      textContent: "✕",
      onclick: () => cerrar()
    })
  ]);

  const cuerpo = el("div", {}, [contenidoNodo]);

  const pie = el("div", {
    style: "display: flex; justify-content: flex-end; gap: 0.75rem; margin-top: 1.5rem; border-top: 1px solid var(--borde-suave); padding-top: 1rem;"
  }, acciones.map(a => el("button", {
    className: `btn btn-${a.tipo || "secundario"}`,
    textContent: a.texto,
    onclick: () => {
      if (a.onClick) a.onClick(cerrar);
      else cerrar();
    }
  })));

  contenido.appendChild(cabecera);
  contenido.appendChild(cuerpo);
  if (acciones.length > 0) contenido.appendChild(pie);
  overlay.appendChild(contenido);
  document.body.appendChild(overlay);

  function cerrar() {
    overlay.classList.remove("abierto");
    setTimeout(() => overlay.remove(), 220);
  }

  // Cerrar al dar click fuera
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) cerrar();
  });

  // Cerrar con Escape
  const onKey = (e) => {
    if (e.key === "Escape") {
      cerrar();
      document.removeEventListener("keydown", onKey);
    }
  };
  document.addEventListener("keydown", onKey);

  requestAnimationFrame(() => {
    overlay.classList.add("abierto");
  });

  return { cerrar };
}
