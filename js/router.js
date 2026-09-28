/**
 * Enrutador por Hash para la SPA · Avancemos
 */

export class Router {
  constructor(rutas, onCambioRuta = null) {
    this.rutas = rutas;
    this.onCambioRuta = onCambioRuta;
    window.addEventListener("hashchange", () => this.resolverRuta());
  }

  iniciar() {
    if (!window.location.hash) {
      window.location.hash = "#/inicio";
    } else {
      this.resolverRuta();
    }
  }

  resolverRuta() {
    const hash = window.location.hash.slice(1) || "/inicio";
    const [rutaSinQuery, queryString] = hash.split("?");
    const query = new URLSearchParams(queryString || "");

    for (const patron in this.rutas) {
      const paramNombres = [];
      const regexPatron = patron.replace(/:([a-zA-Z0-9_]+)/g, (_, nombre) => {
        paramNombres.push(nombre);
        return "([^/]+)";
      });

      const match = rutaSinQuery.match(new RegExp(`^${regexPatron}$`));
      if (match) {
        const params = {};
        paramNombres.forEach((nombre, i) => {
          params[nombre] = match[i + 1];
        });

        if (this.onCambioRuta) {
          this.onCambioRuta(patron, params, query);
        }
        this.rutas[patron](params, query);
        return;
      }
    }

    // Ruta por defecto si no hace match
    if (this.rutas["/inicio"]) {
      this.rutas["/inicio"]({}, query);
    }
  }
}
