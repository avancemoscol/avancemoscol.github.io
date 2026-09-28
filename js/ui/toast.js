/**
 * Gestor de Notificaciones Toast Flotantes · Avancemos
 */

let contenedorToast = null;

function obtenerContenedor() {
  if (!contenedorToast) {
    contenedorToast = document.createElement("div");
    contenedorToast.className = "toast-contenedor";
    document.body.appendChild(contenedorToast);
  }
  return contenedorToast;
}

export function mostrarToast(mensaje, tipo = "exito", duracion = 4000) {
  const contenedor = obtenerContenedor();

  const toast = document.createElement("div");
  toast.className = `toast toast-${tipo}`;
  toast.textContent = mensaje;

  contenedor.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = "0";
    toast.style.transform = "translateY(10px)";
    toast.style.transition = "all 200ms ease-out";
    setTimeout(() => {
      toast.remove();
    }, 200);
  }, duracion);
}
