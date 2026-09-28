/**
 * Cuentas Oficiales de Avancemos
 * Crea la cuenta nacional (@avancemos) y una cuenta por cada departamento (@avancemos_{slug})
 * con tipo_cuenta = 'oficial' e insignia dorada.
 */
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";

const SUPABASE_URL = "https://zxlqwhjlgmoqemcuseek.supabase.co";
// La llave service_role se lee de variable de entorno
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SERVICE_ROLE_KEY) {
  console.error("Falta SUPABASE_SERVICE_ROLE_KEY en el entorno.");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false }
});

async function main() {
  console.log("Iniciando creación de cuentas oficiales...");
  
  // 1. Obtener departamentos
  const { data: deptos, error: errDeptos } = await supabase
    .from("departamentos")
    .select("id, nombre, slug");

  if (errDeptos) throw errDeptos;

  const cuentas = [
    {
      email: "colombia@oficial.avancemos.co",
      username: "avancemos",
      nombre: "Avancemos Colombia",
      bio: "Cuenta oficial del Movimiento Político Avancemos en Colombia. Ni extremos ni excusas: soluciones.",
      departamento_id: null
    },
    ...deptos.map(d => ({
      email: `${d.slug}@oficial.avancemos.co`,
      username: `avancemos_${d.slug.replace(/-/g, "_")}`,
      nombre: `Avancemos ${d.nombre}`,
      bio: `Cuenta oficial de Avancemos en ${d.nombre}. Soluciones construidas desde las regiones.`,
      departamento_id: d.id
    }))
  ];

  for (const c of cuentas) {
    try {
      // Crear usuario de autenticación con contraseña aleatoria
      const dummyPass = "OficialAvancemos" + Math.random().toString(36).slice(-8) + "!2026";
      const { data: uData, error: uErr } = await supabase.auth.admin.createUser({
        email: c.email,
        password: dummyPass,
        email_confirm: true,
        user_metadata: {
          nombre: c.nombre,
          username: c.username,
          departamento_id: c.departamento_id
        }
      });

      const uid = uData?.user?.id;
      if (uid) {
        // Actualizar perfil a oficial con insignia dorada y estado activo
        await supabase.from("perfiles").update({
          tipo_cuenta: "oficial",
          estado: "activo",
          insignia: "dorada",
          perfil_publico: true,
          bio: c.bio
        }).eq("id", uid);

        // Aprobar solicitud automática
        await supabase.from("solicitudes").update({
          estado: "aprobado"
        }).eq("user_id", uid);

        console.log(`✓ Cuenta creada: @${c.username}`);
      }
    } catch (e) {
      console.warn(`Aviso para @${c.username}:`, e.message);
    }
  }

  console.log("Cuentas oficiales procesadas.");
}

main().catch(console.error);
