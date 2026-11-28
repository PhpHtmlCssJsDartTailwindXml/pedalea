-- 1) Preferencias de notificaciones (Configuración → Notificaciones).
--    La Edge Function send-push no envía el push de un tipo apagado (el aviso
--    igual queda en la campana). Sin fila = todo encendido.
-- 2) Vigencia de las alertas: «¿Sigue ahí?» al pasar cerca, y las alertas que
--    nadie confirma se desactivan solas.

-- ── 1) Preferencias ─────────────────────────────────────────────────────────
create table if not exists public.notification_prefs (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  messages   boolean not null default true,  -- mensajes directos y de grupos
  social     boolean not null default true,  -- seguidores, me gusta, comentarios
  impact     boolean not null default true,  -- «Tu alerta ya ayudó a…»
  weekly     boolean not null default true,  -- resumen semanal
  streak     boolean not null default true,  -- recordatorio de racha
  news       boolean not null default true,  -- versiones nuevas y promociones
  updated_at timestamptz not null default now()
);

alter table public.notification_prefs enable row level security;

drop policy if exists notification_prefs_select_own on public.notification_prefs;
create policy notification_prefs_select_own on public.notification_prefs
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists notification_prefs_insert_own on public.notification_prefs;
create policy notification_prefs_insert_own on public.notification_prefs
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists notification_prefs_update_own on public.notification_prefs;
create policy notification_prefs_update_own on public.notification_prefs
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.notification_prefs from anon;
grant select, insert, update on public.notification_prefs to authenticated;

-- ── 2) Vigencia de las alertas ──────────────────────────────────────────────
-- Última vez que alguien confirmó que la alerta sigue ahí.
alter table public.bike_alerts add column if not exists confirmed_at timestamptz;

-- Mismo voto de siempre, más:
--  • «Sigue ahí» (up) renueva confirmed_at.
--  • Con 3 o más «Ya no está» (down) y más que «Sigue ahí», se desactiva.
create or replace function public.vote_alert(p_alert uuid, p_action text)
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid  uuid := auth.uid();
  v_me   text;
  v_up   jsonb;
  v_down jsonb;
  v_owner uuid;
  v_changed boolean := true;
  v_active boolean := true;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  v_me := v_uid::text;

  select coalesce(voters_up, '[]'::jsonb), coalesce(voters_down, '[]'::jsonb), user_id
    into v_up, v_down, v_owner
    from public.bike_alerts
   where id = p_alert
   for update;
  if not found then
    raise exception 'not_found';
  end if;
  if v_owner = v_uid then
    raise exception 'own_alert';
  end if;

  if p_action = 'up' then
    if v_up ? v_me then v_changed := false;
    else v_up := v_up || to_jsonb(v_me); end if;
    v_down := v_down - v_me;
  elsif p_action = 'down' then
    if v_down ? v_me then v_changed := false;
    else v_down := v_down || to_jsonb(v_me); end if;
    v_up := v_up - v_me;
  elsif p_action = 'remove_up' then
    v_changed := v_up ? v_me;
    v_up := v_up - v_me;
  elsif p_action = 'remove_down' then
    v_changed := v_down ? v_me;
    v_down := v_down - v_me;
  else
    raise exception 'bad_action';
  end if;

  if jsonb_array_length(v_down) >= 3
     and jsonb_array_length(v_down) > jsonb_array_length(v_up) then
    v_active := false;
  end if;

  update public.bike_alerts
     set voters_up    = v_up,
         voters_down  = v_down,
         votes_up     = jsonb_array_length(v_up),
         votes_down   = jsonb_array_length(v_down),
         confirmed_at = case when p_action = 'up' then now() else confirmed_at end,
         is_active    = case when v_active then is_active else false end
   where id = p_alert;

  return json_build_object(
    'changed', v_changed,
    'votes_up', jsonb_array_length(v_up),
    'votes_down', jsonb_array_length(v_down),
    'is_active', v_active
  );
end;
$$;

revoke all on function public.vote_alert(uuid, text) from public, anon;
grant execute on function public.vote_alert(uuid, text) to authenticated;

-- Desactiva las alertas que nadie confirmó dentro de su vigencia (se cuenta
-- desde la última confirmación o, si no hay, desde que se creó). Debe
-- coincidir con _alertLifeHours() en la app.
create or replace function public.expire_old_alerts()
returns integer
language sql
security definer
set search_path to 'public'
as $$
  with expired as (
    update public.bike_alerts
       set is_active = false
     where is_active
       and coalesce(confirmed_at, created_at) < now() - case type
             when 'accident'     then interval '24 hours'
             when 'theft'        then interval '48 hours'
             when 'danger'       then interval '7 days'
             when 'construction' then interval '21 days'
             else interval '72 hours'
           end
    returning 1
  )
  select count(*)::integer from expired;
$$;

revoke all on function public.expire_old_alerts() from public, anon, authenticated;

-- Cada hora, a los 15 minutos.
select cron.unschedule('pedalea_expire_alerts')
 where exists (select 1 from cron.job where jobname = 'pedalea_expire_alerts');
select cron.schedule('pedalea_expire_alerts', '15 * * * *', 'select public.expire_old_alerts()');
