const CACHE_NAME = "avancemos-v1";
const ARCHIVOS_CACHE = [
  "/",
  "/index.html",
  "/quienes-somos.html",
  "/el-centro.html",
  "/referentes.html",
  "/propuestas.html",
  "/eventos.html",
  "/offline.html",
  "/css/tokens.css",
  "/css/base.css",
  "/css/componentes.css",
  "/css/publico.css",
  "/assets/logo.svg",
  "/assets/icono.svg",
  "/assets/avatar-default.svg",
  "/data/colombia-departamentos.geojson"
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(ARCHIVOS_CACHE);
    })
  );
  self.skipWaiting();
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((k) => {
          if (k !== CACHE_NAME) return caches.delete(k);
        })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener("fetch", (e) => {
  if (e.request.method !== "GET") return;

  e.respondWith(
    fetch(e.request)
      .then((res) => {
        // Guardar copia fresca en caché para assets estáticos
        if (res.status === 200 && e.request.url.startsWith(self.location.origin)) {
          const resClon = res.clone();
          caches.open(CACHE_NAME).then((c) => c.put(e.request, resClon));
        }
        return res;
      })
      .catch(() => {
        return caches.match(e.request).then((resCache) => {
          if (resCache) return resCache;
          if (e.request.mode === "navigate") {
            return caches.match("/offline.html");
          }
        });
      })
  );
});
