/**
 * Widget Flotante de Soporte, Asistente IA y Radicación de Casos · Avancemos
 * Atiende dudas tanto de visitantes como de usuarios inscritos en todas las páginas.
 */

import { el, escaparTexto as esc } from "../util/texto-seguro.js";
import { resolverDudaConIA, radicarCasoSoporte, consultarCasoSoporte, enviarMensajeACaso, MAX_CARACTERES_PREGUNTA } from "../servicios/soporte.js";
import { obtenerUsuarioActual } from "../auth.js";
import { mostrarToast } from "./toast.js";

export function inicializarWidgetSoporte() {
  if (document.getElementById("widget-soporte-contenedor")) return;

  const contenedor = el("div", { id: "widget-soporte-contenedor" });

  // Botón flotante
  const botonFlotante = el("button", {
    className: "widget-soporte-boton",
    "aria-label": "Abrir soporte y resolvedor de dudas",
    onclick: () => toggleWidget()
  }, [
    el("span", { textContent: "💬" }),
    el("span", { textContent: "Dudas y Soporte" })
  ]);

  // Panel flotante
  const panel = el("div", { className: "widget-soporte-panel", id: "widget-soporte-panel" });

  // Encabezado
  const header = el("div", { className: "widget-soporte-header" }, [
    el("div", {}, [
      el("div", { textContent: "Asistente y Soporte Avancemos", style: "font-weight: 700; font-size: 0.95rem;" }),
      el("div", { textContent: "Dudas de registro, propuestas y casos", style: "font-size: 0.75rem; opacity: 0.8;" })
    ]),
    el("button", {
      style: "background: none; border: none; color: #fff; cursor: pointer; font-size: 1.1rem;",
      textContent: "✕",
      onclick: () => toggleWidget()
    })
  ]);

  // Pestañas
  const pestanas = el("div", {
    style: "display: flex; border-bottom: 1px solid var(--borde); background: var(--marfil);"
  }, [
    crearPestana("chat", "Preguntar a IA", true),
    crearPestana("radicar", "Radicar Caso", false),
    crearPestana("consultar", "Consultar Caso", false)
  ]);

  const cuerpo = el("div", { className: "widget-soporte-cuerpo" });

  panel.appendChild(header);
  panel.appendChild(pestanas);
  panel.appendChild(cuerpo);

  contenedor.appendChild(botonFlotante);
  contenedor.appendChild(panel);
  document.body.appendChild(contenedor);

  let pestanaActual = "chat";
  renderizarVista(pestanaActual, cuerpo);

  function crearPestana(id, titulo, activa) {
    const btn = el("button", {
      className: `pestana ${activa ? "activa" : ""}`,
      style: "flex: 1; text-align: center; padding: 0.65rem 0.25rem; font-size: 0.8rem;",
      textContent: titulo,
      onclick: () => {
        panel.querySelectorAll(".pestana").forEach(p => p.classList.remove("activa"));
        btn.classList.add("activa");
        pestanaActual = id;
        renderizarVista(id, cuerpo);
      }
    });
    return btn;
  }

  function toggleWidget() {
    const abierto = panel.classList.toggle("activo");
    document.body.classList.toggle("widget-abierto-movil", abierto);
    if (abierto) {
      const campo = panel.querySelector("input, textarea");
      if (campo && window.matchMedia("(min-width: 769px)").matches) campo.focus();
    }
  }
}

async function renderizarVista(vista, contenedor) {
  contenedor.innerHTML = "";
  const usuario = await obtenerUsuarioActual();

  if (vista === "chat") {
    // Vista de Chat Asistente IA
    const listaMensajes = el("div", {
      style: "flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 0.75rem; padding-bottom: 0.5rem;"
    }, [
      el("div", {
        style: "background: rgba(11, 122, 110, 0.08); padding: 0.75rem; border-radius: var(--radio-md); font-size: var(--fs-xs); line-height: 1.45;"
      }, [
        el("strong", { textContent: "¡Hola! " }),
        el("span", {
          textContent: "Soy el orientador de Avancemos. Puedo resolver tus dudas sobre nuestra propuesta de centro, el proceso de inscripción gratuita, cómo participar o resolver inquietudes técnicas."
        })
      ])
    ]);

    const inputMsg = el("input", {
      className: "campo-input",
      placeholder: "Escribe tu pregunta (máx. 120 caracteres)...",
      maxlength: String(MAX_CARACTERES_PREGUNTA),
      "aria-label": "Tu pregunta para el asistente",
      style: "flex: 1; font-size: 0.85rem;"
    });
    const contadorChars = el("span", { className: "widget-contador", textContent: `0/${MAX_CARACTERES_PREGUNTA}` });
    const infoUsos = el("span", {
      className: "widget-contador",
      textContent: usuario ? "Hasta 5 preguntas al día." : "Visitantes: 3 preguntas al día. Regístrate para tener más."
    });
    inputMsg.addEventListener("input", () => {
      contadorChars.textContent = `${inputMsg.value.length}/${MAX_CARACTERES_PREGUNTA}`;
    });

    const btnEnviar = el("button", {
      className: "btn btn-primario btn-sm",
      textContent: "Enviar",
      onclick: async () => {
        const txt = inputMsg.value.trim().slice(0, MAX_CARACTERES_PREGUNTA);
        if (!txt || btnEnviar.disabled) return;

        // Agregar mensaje usuario
        listaMensajes.appendChild(el("div", {
          style: "align-self: flex-end; background: var(--turquesa); color: #fff; padding: 0.5rem 0.85rem; border-radius: 12px 12px 2px 12px; font-size: 0.85rem; max-width: 85%;"
        }, [txt]));

        inputMsg.value = "";
        listaMensajes.scrollTop = listaMensajes.scrollHeight;

        // Estado pensando
        const pensando = el("div", {
          style: "align-self: flex-start; color: var(--texto-suave); font-size: 0.75rem; font-style: italic;"
        }, ["Consultando respuesta..."]);
        listaMensajes.appendChild(pensando);
        listaMensajes.scrollTop = listaMensajes.scrollHeight;

        btnEnviar.disabled = true;
        try {
          const res = await resolverDudaConIA(txt);
          pensando.remove();
          listaMensajes.appendChild(el("div", {
            style: `align-self: flex-start; background: var(--superficie); border: 1px solid ${res.limite ? "var(--ambar)" : "var(--borde)"}; padding: 0.65rem 0.85rem; border-radius: 12px 12px 12px 2px; font-size: 0.85rem; max-width: 90%; line-height: 1.45; white-space: pre-wrap;`
          }, formatearRespuesta(res.respuesta)));
          if (res.restantes !== null && res.restantes !== undefined) {
            infoUsos.textContent = res.restantes > 0
              ? `Te quedan ${res.restantes} ${res.restantes === 1 ? "pregunta" : "preguntas"} hoy.`
              : "Llegaste al límite de hoy. Puedes radicar un caso en la pestaña siguiente.";
          }
          if (res.limite) {
            inputMsg.disabled = true;
            inputMsg.placeholder = "Límite diario alcanzado";
          }
          contadorChars.textContent = `0/${MAX_CARACTERES_PREGUNTA}`;
          listaMensajes.scrollTop = listaMensajes.scrollHeight;
        } catch (e) {
          pensando.remove();
          listaMensajes.appendChild(el("div", {
            style: "color: var(--error); font-size: 0.8rem;"
          }, ["No pudimos conectar en este momento. Puedes radicar tu caso en la siguiente pestaña."]));
        } finally {
          btnEnviar.disabled = inputMsg.disabled;
        }
      }
    });

    inputMsg.addEventListener("keydown", (e) => {
      if (e.key === "Enter") btnEnviar.click();
    });

    const boxInput = el("div", {
      style: "display: flex; gap: 0.5rem; border-top: 1px solid var(--borde-suave); padding-top: 0.75rem;"
    }, [inputMsg, btnEnviar]);

    contenedor.appendChild(listaMensajes);
    contenedor.appendChild(boxInput);
    contenedor.appendChild(el("div", { className: "widget-pie-info" }, [infoUsos, contadorChars]));
  } else if (vista === "radicar") {
    // Vista de Radicación de Caso Formal
    const form = el("form", {
      style: "display: flex; flex-direction: column; gap: 0.75rem;",
      onsubmit: async (e) => {
        e.preventDefault();
        const fData = new FormData(form);
        const btnSub = form.querySelector("button[type='submit']");
        btnSub.disabled = true;
        btnSub.textContent = "Radicando caso...";

        try {
          const res = await radicarCasoSoporte({
            nombre: fData.get("nombre"),
            correo: fData.get("correo"),
            telefono: fData.get("telefono") || null,
            categoria: fData.get("categoria"),
            asunto: fData.get("asunto"),
            descripcion: fData.get("descripcion")
          });

          mostrarToast(`Caso radicado: ${res.numero_radicado}`, "exito", 6000);
          contenedor.innerHTML = `
            <div style="text-align: center; padding: 2rem 1rem;">
              <div style="font-size: 2.5rem; margin-bottom: 0.5rem;">✅</div>
              <h4 style="color: var(--turquesa);">¡Caso Radicado Exitosamente!</h4>
              <p style="margin: 1rem 0; font-size: 0.9rem;">Tu número de radicado oficial es:</p>
              <div style="font-family: var(--fuente-mono); font-size: 1.25rem; font-weight: 700; background: var(--marfil); padding: 0.5rem 1rem; border-radius: var(--radio-md); border: 1px dashed var(--turquesa); display: inline-block;">
                ${res.numero_radicado}
              </div>
              <p style="margin-top: 1rem; font-size: 0.8rem; color: var(--texto-suave);">
                Guarda este código para hacerle seguimiento en la pestaña "Consultar Caso". Te responderemos al correo que registraste.
              </p>
            </div>
          `;
        } catch (err) {
          btnSub.disabled = false;
          btnSub.textContent = "Radicar Caso";
          mostrarToast(err.message || "Error al radicar caso", "error");
        }
      }
    }, [
      el("div", { className: "campo" }, [
        el("label", { className: "campo-etiqueta", textContent: "Nombre completo *" }),
        el("input", {
          className: "campo-input",
          name: "nombre",
          required: true,
          value: usuario?.user_metadata?.nombre || ""
        })
      ]),
      el("div", { className: "campo" }, [
        el("label", { className: "campo-etiqueta", textContent: "Correo de contacto *" }),
        el("input", {
          className: "campo-input",
          name: "correo",
          type: "email",
          required: true,
          value: usuario?.email || ""
        })
      ]),
      el("div", { className: "campo" }, [
        el("label", { className: "campo-etiqueta", textContent: "Categoría *" }),
        el("select", { className: "campo-select", name: "categoria" }, [
          el("option", { value: "inscripcion", textContent: "Inscripción o estado de cuenta" }),
          el("option", { value: "verificacion", textContent: "Insignia o Verificación" }),
          el("option", { value: "territorio_grupo", textContent: "Grupos de WhatsApp o Territorio" }),
          el("option", { value: "problema_tecnico", textContent: "Inconveniente técnico en la plataforma" }),
          el("option", { value: "pregunta_politica", textContent: "Propuestas o programa de gobierno" }),
          el("option", { value: "otro", textContent: "Otra consulta general" })
        ])
      ]),
      el("div", { className: "campo" }, [
        el("label", { className: "campo-etiqueta", textContent: "Asunto *" }),
        el("input", { className: "campo-input", name: "asunto", required: true, placeholder: "Ej. Consulta sobre aprobación en Caldas" })
      ]),
      el("div", { className: "campo" }, [
        el("label", { className: "campo-etiqueta", textContent: "Detalle de tu solicitud *" }),
        el("textarea", {
          className: "campo-textarea",
          name: "descripcion",
          required: true,
          rows: 3,
          placeholder: "Describe tu duda o inconveniente claramente..."
        })
      ]),
      el("button", {
        type: "submit",
        className: "btn btn-primario",
        textContent: "Radicar Caso",
        style: "margin-top: 0.5rem;"
      })
    ]);

    contenedor.appendChild(form);
  } else if (vista === "consultar") {
    // Vista de Consulta de Radicado Existente
    const formConsulta = el("form", {
      style: "display: flex; flex-direction: column; gap: 0.75rem;",
      onsubmit: async (e) => {
        e.preventDefault();
        const fData = new FormData(formConsulta);
        const radicado = fData.get("radicado");
        const correo = fData.get("correo");

        const resultadoBox = contenedor.querySelector("#resultado-caso-box");
        resultadoBox.textContent = "Buscando caso...";

        try {
          const res = await consultarCasoSoporte(radicado, correo);
          if (!res.encontrado) {
            resultadoBox.innerHTML = `<p style="color: var(--error);">${res.mensaje}</p>`;
            return;
          }

          const c = res.caso;
          resultadoBox.innerHTML = `
            <div style="background: var(--marfil); padding: 0.85rem; border-radius: var(--radio-md); border: 1px solid var(--borde);">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
                <strong style="color: var(--azul-noche);">${c.numero_radicado}</strong>
                <span class="chip chip-${c.estado === 'resuelto' ? 'turquesa' : 'ambar'}">${c.estado}</span>
              </div>
              <p style="font-weight: 600; font-size: 0.85rem; margin-bottom: 0.25rem;">${esc(c.asunto)}</p>
              ${c.respuesta_oficial ? `
                <div style="margin-top: 0.75rem; background: var(--superficie); padding: 0.75rem; border-radius: var(--radio-md); border-left: 3px solid var(--turquesa);">
                  <strong style="color: var(--turquesa); font-size: 0.75rem;">Respuesta del equipo de moderación:</strong>
                  <p style="font-size: 0.8rem; margin-top: 0.25rem;">${esc(c.respuesta_oficial)}</p>
                </div>
              ` : '<p style="font-size: 0.75rem; color: var(--texto-suave); margin-top: 0.5rem;">Tu caso se encuentra en revisión por el equipo.</p>'}
            </div>
          `;
        } catch (err) {
          resultadoBox.innerHTML = `<p style="color: var(--error);">${err.message}</p>`;
        }
      }
    }, [
      el("div", { className: "campo" }, [
        el("label", { className: "campo-etiqueta", textContent: "Número de radicado (Ej: RAD-2026-XXXXXX) *" }),
        el("input", { className: "campo-input", name: "radicado", required: true, placeholder: "RAD-2026-..." })
      ]),
      el("div", { className: "campo" }, [
        el("label", { className: "campo-etiqueta", textContent: "Correo con el que radicaste *" }),
        el("input", { className: "campo-input", name: "correo", type: "email", required: true, value: usuario?.email || "" })
      ]),
      el("button", {
        type: "submit",
        className: "btn btn-primario btn-sm",
        textContent: "Consultar Estado"
      }),
      el("div", { id: "resultado-caso-box", style: "margin-top: 1rem;" })
    ]);

    contenedor.appendChild(formConsulta);
  }
}

// Convierte **negritas** del asistente en <strong> usando nodos DOM (sin innerHTML)
function formatearRespuesta(texto) {
  const limpio = String(texto || "").replace(/^\s*[*-]\s+/gm, "• ").replace(/\n{3,}/g, "\n\n").trim();
  return limpio.split(/(\*\*[^*]+\*\*)/g).filter(Boolean).map(parte =>
    parte.startsWith("**") && parte.endsWith("**")
      ? el("strong", { textContent: parte.slice(2, -2) })
      : document.createTextNode(parte.replace(/\*/g, ""))
  );
}
