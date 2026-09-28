/**
 * Procesamiento de Imágenes y Medios en el Navegador · Avancemos
 * Comprime imágenes a WebP (máx. 1600px) antes de subir.
 * Genera póster de video con canvas.
 */

export async function comprimirImagenWebP(archivo, maxDim = 1600, calidad = 0.82) {
  // createImageBitmap decodifica sin cargar la imagen en base64 (menos memoria en celulares)
  let fuente;
  let liberar = () => {};
  try {
    fuente = await createImageBitmap(archivo, { imageOrientation: "from-image" });
    liberar = () => fuente.close && fuente.close();
  } catch (_) {
    const url = URL.createObjectURL(archivo);
    fuente = await new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error("Formato de imagen no soportado por el navegador"));
      img.src = url;
    });
    liberar = () => URL.revokeObjectURL(url);
  }

  let ancho = fuente.width;
  let alto = fuente.height;
  if (ancho > maxDim || alto > maxDim) {
    const escala = maxDim / Math.max(ancho, alto);
    ancho = Math.round(ancho * escala);
    alto = Math.round(alto * escala);
  }

  const canvas = document.createElement("canvas");
  canvas.width = ancho;
  canvas.height = alto;
  canvas.getContext("2d").drawImage(fuente, 0, 0, ancho, alto);
  liberar();

  const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/webp", calidad));
  // Safari antiguo no genera WebP: devuelve PNG; en ese caso usar JPEG
  const final = blob && blob.type === "image/webp"
    ? blob
    : await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", calidad));
  if (!final) throw new Error("Error al comprimir imagen");

  const extension = final.type === "image/webp" ? "webp" : "jpg";
  const nombre = (archivo.name || "imagen").replace(/\.[^.]+$/, "") + "." + extension;
  return { archivo: new File([final], nombre, { type: final.type }), ancho, alto };
}

export async function capturarPosterVideo(archivoVideo) {
  return new Promise((resolve) => {
    const video = document.createElement("video");
    video.preload = "metadata";
    video.src = URL.createObjectURL(archivoVideo);
    video.muted = true;
    video.playsInline = true;

    video.onloadeddata = () => {
      video.currentTime = Math.min(1.0, video.duration / 2);
    };

    video.onseeked = () => {
      const canvas = document.createElement("canvas");
      canvas.width = video.videoWidth || 640;
      canvas.height = video.videoHeight || 360;
      const ctx = canvas.getContext("2d");
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

      canvas.toBlob((blob) => {
        URL.revokeObjectURL(video.src);
        resolve(blob);
      }, "image/webp", 0.8);
    };

    video.onerror = () => {
      resolve(null);
    };
  });
}
