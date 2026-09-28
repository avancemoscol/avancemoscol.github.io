/**
 * Procesamiento de Imágenes y Medios en el Navegador · Avancemos
 * Comprime imágenes a WebP (máx. 1600px) antes de subir.
 * Genera póster de video con canvas.
 */

export async function comprimirImagenWebP(archivo, maxDim = 1600, calidad = 0.82) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        let ancho = img.width;
        let alto = img.height;

        if (ancho > maxDim || alto > maxDim) {
          if (ancho > alto) {
            alto = Math.round((alto * maxDim) / ancho);
            ancho = maxDim;
          } else {
            ancho = Math.round((ancho * maxDim) / alto);
            alto = maxDim;
          }
        }

        const canvas = document.createElement("canvas");
        canvas.width = ancho;
        canvas.height = alto;
        const ctx = canvas.getContext("2d");
        ctx.drawImage(img, 0, 0, ancho, alto);

        canvas.toBlob(
          (blob) => {
            if (!blob) return reject(new Error("Error al comprimir imagen"));
            const nombreWebp = archivo.name.replace(/\.[^.]+$/, "") + ".webp";
            const archivoWebp = new File([blob], nombreWebp, { type: "image/webp" });
            resolve({ archivo: archivoWebp, ancho, alto });
          },
          "image/webp",
          calidad
        );
      };
      img.onerror = reject;
      img.src = e.target.result;
    };
    reader.onerror = reject;
    reader.readAsDataURL(archivo);
  });
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
