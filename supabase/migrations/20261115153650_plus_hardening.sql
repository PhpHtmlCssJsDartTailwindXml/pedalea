-- Endurece las funciones de Pedalea Plus en el servidor.
--
-- Antes:
--  * Eventos: el límite de 2 eventos activos, los eventos privados y unirse a
--    un privado solo se validaban en la app. Cualquier usuario con sesión
--    podía además modificar CUALQUIER evento (policy UPDATE abierta) y leer
--    el hash de la contraseña de los eventos privados.
--  * profiles.is_plus solo se recalculaba cuando cambiaba la tabla
--    subscriptions: si una suscripción vencía sin renovarse, el servidor
--    seguía tratando al usuario como Plus (bicis / momentos sin límite).
--
-- Después:
--  * plus_active(uid): única fuente de verdad (suscripción activa y vigente).
--  * Triggers de bicis, momentos y eventos usan plus_active().
--  * Unirse / salir de eventos solo vía RPC (join_event / leave_event).
--  * UPDATE de eventos solo para su creador.
--    (El hash de la contraseña se movió después a la tabla privada
--     event_secrets en 20261115234811_security_stage1.sql.)
--  * sync_my_plus(): la app la llama al abrir para corregir is_plus vencido.

-- 1. Fuente de verdad ---------------------------------------------------------
create or replace function public.plus_active(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.subscriptions s
    where s.user_id = p_user
      and s.is_active = true
      and (s.expires_at is null or s.expires_at > now())
  );
$$;
revoke all on function public.plus_active(uuid) from public, anon;
grant execute on function public.plus_active(uuid) to authenticated, service_role;

-- Recalcula profiles.is_plus del usuario actual (medalla, etc.).
create or replace function public.sync_my_plus()
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_active boolean;
begin
  if v_uid is null then
    return false;
  end if;
  v_active := public.plus_active(v_uid);
  update public.profiles set is_plus = v_active
   where id = v_uid and is_plus is distinct from v_active;
  return v_active;
end;
$$;
revoke all on function public.sync_my_plus() from public, anon;
grant execute on function public.sync_my_plus() to authenticated;

-- 2. Bicis: 1 gratis ----------------------------------------------------------
create or replace function public.bikes_before_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_count int;
begin
  select count(*) into v_count from public.bikes where user_id = new.user_id;
  if v_count >= 1 and not public.plus_active(new.user_id) then
    raise exception 'bike_limit_free';
  end if;
  if v_count >= 20 then
    raise exception 'bike_limit_max';
  end if;
  new.app_km := 0; -- los km de la app solo se suman con add_bike_km()
  new.is_active := not exists (
    select 1 from public.bikes where user_id = new.user_id and is_active
  );
  return new;
end;
$$;

-- 3. Momentos: 2 al día gratis --------------------------------------------------
create or replace function public.enforce_daily_post_limit()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_today_count int;
  v_day_start timestamptz;
begin
  if public.plus_active(new.user_id) then
    return new;
  end if;

  v_day_start := (date_trunc('day', (now() at time zone 'America/Santiago')))
                 at time zone 'America/Santiago';

  select count(*) into v_today_count
    from public.posts
    where user_id = new.user_id
      and created_at >= v_day_start;

  if v_today_count >= 2 then
    raise exception 'daily_post_limit'
      using hint = 'El plan gratis permite 2 momentos al día. Hazte Pedalea Plus para publicar sin límite.';
  end if;

  return new;
end;
$$;

-- 4. Eventos ------------------------------------------------------------------
-- 4a. Al crear: privados y más de 2 activos solo con Plus. El creador parte
--     como único participante (no se puede inflar la lista al insertar).
create or replace function public.events_before_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_plus boolean;
  v_active int;
begin
  if public.is_trusted_writer() then
    return new;
  end if;
  if new.user_id is distinct from auth.uid() then
    raise exception 'not_allowed';
  end if;

  v_plus := public.plus_active(new.user_id);

  if coalesce(new.is_private, false) and not v_plus then
    raise exception 'plus_required_private_event';
  end if;

  if not v_plus then
    select count(*) into v_active
      from public.events
     where user_id = new.user_id and is_active = true;
    if v_active >= 2 then
      raise exception 'event_limit_free';
    end if;
  end if;

  new.participants_ids := jsonb_build_array(new.user_id::text);
  new.participants_count := 1;
  new.is_active := true;
  return new;
end;
$$;

drop trigger if exists events_before_insert on public.events;
create trigger events_before_insert
  before insert on public.events
  for each row execute function public.events_before_insert();

-- 4b. Solo el creador puede modificar su evento (antes: cualquiera).
drop policy if exists events_update_authenticated on public.events;
drop policy if exists events_update_own on public.events;
create policy events_update_own on public.events
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- El creador tampoco puede volver privado su evento sin Plus ni tocar la
-- lista de participantes a mano (eso pasa solo por join/leave).
create or replace function public.events_before_update()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if public.is_trusted_writer() then
    return new;
  end if;
  if coalesce(new.is_private, false) and not coalesce(old.is_private, false)
     and not public.plus_active(old.user_id) then
    raise exception 'plus_required_private_event';
  end if;
  if current_setting('pedalea.event_membership', true) is distinct from 'on' then
    new.participants_ids := old.participants_ids;
    new.participants_count := old.participants_count;
  end if;
  new.user_id := old.user_id;
  return new;
end;
$$;

drop trigger if exists events_before_update on public.events;
create trigger events_before_update
  before update on public.events
  for each row execute function public.events_before_update();

-- 4c. Unirse. p_password_hash = sha256 hex de la contraseña (lo calcula la app).
create or replace function public.join_event(p_event_id uuid, p_password_hash text default null)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_ev public.events%rowtype;
  v_ids jsonb;
begin
  if v_uid is null then
    return 'error';
  end if;

  select * into v_ev from public.events where id = p_event_id for update;
  if not found or not coalesce(v_ev.is_active, false) then
    return 'error';
  end if;

  v_ids := coalesce(v_ev.participants_ids, '[]'::jsonb);
  if v_ids ? v_uid::text then
    return 'already_joined';
  end if;

  if coalesce(v_ev.is_private, false) and v_ev.user_id <> v_uid then
    if not public.plus_active(v_uid) then
      return 'plus_required';
    end if;
    if v_ev.password_hash is null
       or p_password_hash is null
       or lower(p_password_hash) <> lower(v_ev.password_hash) then
      return 'wrong_password';
    end if;
  end if;

  if v_ev.max_participants is not null
     and jsonb_array_length(v_ids) >= v_ev.max_participants then
    return 'full';
  end if;

  v_ids := v_ids || jsonb_build_array(v_uid::text);
  perform set_config('pedalea.event_membership', 'on', true);
  update public.events
     set participants_ids = v_ids,
         participants_count = jsonb_array_length(v_ids)
   where id = p_event_id;
  perform set_config('pedalea.event_membership', 'off', true);
  return 'ok';
end;
$$;
revoke all on function public.join_event(uuid, text) from public, anon;
grant execute on function public.join_event(uuid, text) to authenticated;

-- 4d. Salir.
create or replace function public.leave_event(p_event_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_ids jsonb;
begin
  if v_uid is null then
    return false;
  end if;
  select coalesce(participants_ids, '[]'::jsonb) into v_ids
    from public.events where id = p_event_id for update;
  if not found or not (v_ids ? v_uid::text) then
    return false;
  end if;
  v_ids := v_ids - v_uid::text;
  perform set_config('pedalea.event_membership', 'on', true);
  update public.events
     set participants_ids = v_ids,
         participants_count = jsonb_array_length(v_ids)
   where id = p_event_id;
  perform set_config('pedalea.event_membership', 'off', true);
  return true;
end;
$$;
revoke all on function public.leave_event(uuid) from public, anon;
grant execute on function public.leave_event(uuid) to authenticated;

-- 5. Corrige ya a quienes tengan is_plus pegado de una suscripción vencida.
update public.profiles p
   set is_plus = public.plus_active(p.id)
 where p.is_plus is distinct from public.plus_active(p.id);
