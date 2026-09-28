/**
 * Menú hamburguesa del sitio público (celulares) · Avancemos
 */

export function inicializarMenuSitio() {
  const boton = document.querySelector(".menu-hamburguesa");
  const menu = document.getElementById("sitio-menu") || document.querySelector(".sitio-menu");
  if (!boton || !menu) return;

  if (!menu.id) menu.id = "sitio-menu";
  boton.setAttribute("aria-controls", menu.id);
  boton.setAttribute("aria-expanded", "false");

  const alternar = (abrir) => {
    const abierto = menu.classList.toggle("abierto", abrir);
    boton.setAttribute("aria-expanded", String(abierto));
    boton.textContent = abierto ? "✕" : "☰";
    boton.setAttribute("aria-label", abierto ? "Cerrar menú" : "Abrir menú");
  };

  boton.removeAttribute("onclick");
  boton.addEventListener("click", () => alternar());
  menu.querySelectorAll("a").forEach(a => a.addEventListener("click", () => alternar(false)));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") alternar(false); });
  document.addEventListener("click", (e) => {
    if (menu.classList.contains("abierto") && !menu.contains(e.target) && !boton.contains(e.target)) alternar(false);
  });
}

inicializarMenuSitio();
