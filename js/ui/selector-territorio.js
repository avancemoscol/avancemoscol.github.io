/**
 * Selector Territorial Dependiente (Departamento -> Municipio -> Localidad) · Avancemos
 */

import { el } from "../util/texto-seguro.js";
import { obtenerDepartamentos, obtenerMunicipios, obtenerLocalidadesBogota } from "../util/divipola.js";

export async function inicializarSelectorTerritorio({
  selectDepto,
  selectMuni,
  campoLocalidad = null,
  selectLocalidad = null,
  deptoInicial = null,
  muniInicial = null,
  localidadInicial = null
}) {
  const deptos = await obtenerDepartamentos();

  selectDepto.innerHTML = "<option value=''>Selecciona departamento...</option>";
  deptos.forEach(d => {
    const opt = el("option", { value: d.id, textContent: d.nombre });
    if (d.id === deptoInicial) opt.selected = true;
    selectDepto.appendChild(opt);
  });

  async function actualizarMunicipios(deptoId) {
    if (!deptoId) {
      selectMuni.innerHTML = "<option value=''>Selecciona municipio...</option>";
      selectMuni.disabled = true;
      if (campoLocalidad) campoLocalidad.style.display = "none";
      return;
    }

    selectMuni.disabled = false;
    selectMuni.innerHTML = "<option value=''>Cargando municipios...</option>";
    const munis = await obtenerMunicipios(deptoId);

    selectMuni.innerHTML = "<option value=''>Selecciona municipio...</option>";
    munis.forEach(m => {
      const opt = el("option", { value: m.id, textContent: m.nombre + (m.es_capital ? " (Capital)" : "") });
      if (m.id === muniInicial) opt.selected = true;
      selectMuni.appendChild(opt);
    });

    // Si es Bogotá (11) mostrar selector de localidades
    if (deptoId === "11" && campoLocalidad && selectLocalidad) {
      campoLocalidad.style.display = "flex";
      const locs = await obtenerLocalidadesBogota();
      selectLocalidad.innerHTML = "<option value=''>Selecciona localidad...</option>";
      locs.forEach(l => {
        const opt = el("option", { value: l.id, textContent: l.nombre });
        if (l.id === Number(localidadInicial)) opt.selected = true;
        selectLocalidad.appendChild(opt);
      });
    } else if (campoLocalidad) {
      campoLocalidad.style.display = "none";
    }
  }

  selectDepto.addEventListener("change", (e) => {
    actualizarMunicipios(e.target.value);
  });

  if (deptoInicial) {
    await actualizarMunicipios(deptoInicial);
  }
}
