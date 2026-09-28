/**
 * Renderizado Seguro y Prevención XSS · Avancemos
 * Regla de oro 5: Nunca innerHTML con datos de usuario.
 * Markdown con marked + DOMPurify.
 */

export function escaparTexto(str) {
  if (!str) return "";
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

export function el(tag, attrs = {}, hijos = []) {
  const elem = document.createElement(tag);
  for (const [clave, valor] of Object.entries(attrs)) {
    if (clave === "className" || clave === "class") {
      elem.className = valor;
    } else if (clave.startsWith("on") && typeof valor === "function") {
      elem.addEventListener(clave.slice(2).toLowerCase(), valor);
    } else if (clave === "textContent") {
      elem.textContent = valor;
    } else {
      elem.setAttribute(clave, valor);
    }
  }

  if (!Array.isArray(hijos)) {
    hijos = [hijos];
  }

  for (const hijo of hijos) {
    if (hijo === null || hijo === undefined) continue;
    if (typeof hijo === "string" || typeof hijo === "number") {
      elem.appendChild(document.createTextNode(String(hijo)));
    } else if (hijo instanceof Node) {
      elem.appendChild(hijo);
    }
  }

  return elem;
}

export async function renderizarMarkdownSeguro(textoMd) {
  if (!textoMd) return "";

  // Si marked y DOMPurify están cargados vía CDN en la ventana
  if (window.marked && window.DOMPurify) {
    const rawHtml = window.marked.parse(textoMd);
    return window.DOMPurify.sanitize(rawHtml);
  }

  // Fallback seguro usando solo escape de texto si la CDN no ha cargado
  return `<p>${escaparTexto(textoMd).replace(/\n\n/g, "</p><p>").replace(/\n/g, "<br>")}</p>`;
}
