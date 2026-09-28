
-- -----------------------------------------------------------------------------
-- Corrección: recursión infinita en la política de conversacion_participantes
-- (la política se consultaba a sí misma). Se usa una función security definer.
-- -----------------------------------------------------------------------------
create or replace function public.es_participante(p_conversacion_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.conversacion_participantes
    where conversacion_id = p_conversacion_id and user_id = (select auth.uid())
  );
$$;
revoke all on function public.es_participante(uuid) from public;
grant execute on function public.es_participante(uuid) to anon, authenticated;

drop policy if exists "participante_ver_participantes" on public.conversacion_participantes;
create policy "participante_ver_participantes" on public.conversacion_participantes for select using (
  user_id = (select auth.uid()) or public.es_participante(conversacion_id)
);

drop policy if exists "participante_ver_conversacion" on public.conversaciones;
create policy "participante_ver_conversacion" on public.conversaciones for select using (
  public.es_participante(id)
);

drop policy if exists "participante_ver_mensajes" on public.mensajes;
create policy "participante_ver_mensajes" on public.mensajes for select using (
  public.es_participante(conversacion_id)
);

drop policy if exists "participante_enviar_mensaje" on public.mensajes;
create policy "participante_enviar_mensaje" on public.mensajes for insert with check (
  autor_id = (select auth.uid()) and public.es_participante(conversacion_id) and (select public.puede_interactuar())
);
