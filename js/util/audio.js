/**
 * Audio eficiente en el navegador · Avancemos
 * - Convierte cualquier audio (WAV, MP3, M4A...) a Opus en contenedor WebM (~48 kbps, voz clara,
 *   unas 20 veces más liviano que WAV) usando WebCodecs cuando el navegador lo soporta.
 * - Graba notas de voz directamente en Opus (o AAC en Safari) con MediaRecorder.
 */

const MAX_SEGUNDOS = 300;          // 5 minutos por audio
const TASA_OPUS = 48000;
const BITRATE = 48000;

async function codificadorOpusDisponible() {
  if (typeof AudioEncoder === "undefined") return false;
  try {
    const { supported } = await AudioEncoder.isConfigSupported({ codec: "opus", sampleRate: TASA_OPUS, numberOfChannels: 1, bitrate: BITRATE });
    return Boolean(supported);
  } catch (_) {
    return false;
  }
}

/**
 * Devuelve { archivo, duracion_s } listo para subir.
 * Si la conversión no es posible, devuelve el original cuando ya viene comprimido.
 */
export async function comprimirAudio(archivo) {
  const tiposComprimidos = ["audio/webm", "audio/ogg", "audio/mpeg", "audio/mp4", "audio/aac", "audio/x-m4a"];
  let buffer;
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    buffer = await ctx.decodeAudioData(await archivo.arrayBuffer());
    ctx.close();
  } catch (_) {
    throw new Error("No se pudo leer el audio. Usa MP3, M4A, OGG, WebM o WAV.");
  }
  if (buffer.duration > MAX_SEGUNDOS) {
    throw new Error(`El audio dura más de ${MAX_SEGUNDOS / 60} minutos.`);
  }

  if (!(await codificadorOpusDisponible())) {
    if (tiposComprimidos.includes(archivo.type)) return { archivo, duracion_s: Math.round(buffer.duration) };
    throw new Error("Tu navegador no puede comprimir este audio. Súbelo en MP3 o M4A.");
  }

  // Remuestrear a 48 kHz mono (formato nativo de Opus)
  const offline = new OfflineAudioContext(1, Math.ceil(buffer.duration * TASA_OPUS), TASA_OPUS);
  const fuente = offline.createBufferSource();
  fuente.buffer = buffer;
  fuente.connect(offline.destination);
  fuente.start();
  const mono = await offline.startRendering();
  const muestras = mono.getChannelData(0);

  const { Muxer, ArrayBufferTarget } = await import("https://cdn.jsdelivr.net/npm/webm-muxer@5.1.4/build/webm-muxer.mjs");
  const muxer = new Muxer({
    target: new ArrayBufferTarget(),
    audio: { codec: "A_OPUS", sampleRate: TASA_OPUS, numberOfChannels: 1 }
  });

  let errorCodificacion = null;
  const encoder = new AudioEncoder({
    output: (chunk, meta) => muxer.addAudioChunk(chunk, meta),
    error: (e) => { errorCodificacion = e; }
  });
  encoder.configure({ codec: "opus", sampleRate: TASA_OPUS, numberOfChannels: 1, bitrate: BITRATE });

  const bloque = TASA_OPUS / 50; // tramas de 20 ms
  for (let i = 0; i < muestras.length; i += bloque) {
    const trozo = muestras.subarray(i, Math.min(i + bloque, muestras.length));
    const datos = new AudioData({
      format: "f32",
      sampleRate: TASA_OPUS,
      numberOfFrames: trozo.length,
      numberOfChannels: 1,
      timestamp: Math.round((i / TASA_OPUS) * 1e6),
      data: trozo
    });
    encoder.encode(datos);
    datos.close();
  }
  await encoder.flush();
  encoder.close();
  if (errorCodificacion) throw errorCodificacion;
  muxer.finalize();

  const nombre = (archivo.name || "audio").replace(/\.[^.]+$/, "") + ".webm";
  const resultado = new File([muxer.target.buffer], nombre, { type: "audio/webm" });
  // Si el original ya era más liviano (p. ej. MP3 de baja tasa), conservarlo
  const final = tiposComprimidos.includes(archivo.type) && archivo.size < resultado.size ? archivo : resultado;
  return { archivo: final, duracion_s: Math.round(buffer.duration) };
}

/**
 * Graba una nota de voz. Devuelve un controlador { detener(): Promise<File>, cancelar() }.
 */
export async function iniciarGrabacion(onTick) {
  if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
    throw new Error("Tu navegador no permite grabar audio.");
  }
  const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } });
  const tipo = ["audio/webm;codecs=opus", "audio/ogg;codecs=opus", "audio/mp4"].find(t => MediaRecorder.isTypeSupported(t)) || "";
  const grabador = new MediaRecorder(stream, tipo ? { mimeType: tipo, audioBitsPerSecond: BITRATE } : undefined);
  const partes = [];
  grabador.ondataavailable = (e) => e.data.size && partes.push(e.data);
  grabador.start(1000);

  const inicio = Date.now();
  const timer = setInterval(() => {
    const seg = Math.floor((Date.now() - inicio) / 1000);
    if (onTick) onTick(seg);
    if (seg >= MAX_SEGUNDOS) controlador.detener();
  }, 500);

  const liberar = () => {
    clearInterval(timer);
    stream.getTracks().forEach(t => t.stop());
  };

  const controlador = {
    detener: () => new Promise((resolve) => {
      if (grabador.state === "inactive") return resolve(null);
      grabador.onstop = () => {
        liberar();
        const mime = (grabador.mimeType || tipo || "audio/webm").split(";")[0];
        const ext = mime.includes("mp4") ? "m4a" : mime.includes("ogg") ? "ogg" : "webm";
        resolve(new File(partes, `nota-de-voz.${ext}`, { type: mime }));
      };
      grabador.stop();
    }),
    cancelar: () => {
      grabador.onstop = null;
      if (grabador.state !== "inactive") grabador.stop();
      liberar();
    }
  };
  return controlador;
}
