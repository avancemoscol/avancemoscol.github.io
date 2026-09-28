import { SignJWT, importPKCS8 } from "npm:jose@5";

let cache: { token: string; exp: number } | null = null;

export async function tokenGoogle(): Promise<string> {
  if (cache && cache.exp > Date.now() + 60_000) return cache.token;

  let sa: { client_email: string; private_key: string };
  const saKeyB64 = Deno.env.get("GCP_SA_KEY_B64");
  if (saKeyB64) {
    sa = JSON.parse(atob(saKeyB64));
  } else {
    // Si se pasa como JSON string directo
    sa = JSON.parse(Deno.env.get("GCP_SA_KEY") || "{}");
  }

  if (!sa.private_key) {
    throw new Error("No se encontró la llave de la cuenta de servicio de GCP.");
  }

  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/cloud-platform" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);

  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion
    })
  });

  if (!r.ok) throw new Error(`OAuth Google ${r.status}: ${await r.text()}`);
  const { access_token, expires_in } = await r.json();
  cache = { token: access_token, exp: Date.now() + expires_in * 1000 };
  return access_token;
}

export function urlModelo(ubicacion: string, modelo: string, metodo: string): string {
  const host = ubicacion === "global" ? "aiplatform.googleapis.com" : `${ubicacion}-aiplatform.googleapis.com`;
  const proyecto = Deno.env.get("GCP_PROJECT_ID") || "botes-506017";
  return `https://${host}/v1/projects/${proyecto}/locations/${ubicacion}/publishers/google/models/${modelo}:${metodo}`;
}
