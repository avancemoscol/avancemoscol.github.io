/**
 * Control de Permisos y Roles en el Cliente · Avancemos
 * Nota: El frontend solo adapta la UX; la seguridad real reside en la base de datos (RLS).
 */

import { supabase } from "./supabase.js";

let permisosCache = null;

export async function cargarPermisos(forzar = false) {
  if (permisosCache && !forzar) return permisosCache;

  try {
    const { data, error } = await supabase.rpc("mis_permisos");
    if (error || !data) {
      permisosCache = { autenticado: false };
    } else {
      permisosCache = data;
    }
  } catch (e) {
    permisosCache = { autenticado: false };
  }
  return permisosCache;
}

export function limpiarPermisos() {
  permisosCache = null;
}

export function esAdminNacional(permisos) {
  return Boolean(permisos?.es_admin_nacional);
}

export function puedeModerarDepto(permisos, deptoId) {
  if (permisos?.es_admin_nacional) return true;
  if (!deptoId) return false;
  return Boolean(permisos?.departamentos_moderacion?.includes(deptoId));
}

export function esModeradorOAdmin(permisos) {
  if (permisos?.es_admin_nacional) return true;
  return Boolean(permisos?.departamentos_moderacion?.length > 0);
}
