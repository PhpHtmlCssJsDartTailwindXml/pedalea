-- SEGURIDAD · ETAPA 1 (ejecutar ANTES de publicar la versión 1.3.3)
--
-- Solo agrega funciones y protecciones compatibles: las versiones antiguas de
-- la app siguen funcionando igual. Los cierres que sí afectan a versiones
-- antiguas están en 20261115234812_security_stage2.sql.

-- 1) Contacto de emergencia: el propio usuario lo lee con esta función.
--    (En la etapa 2 esas columnas dejan de ser legibles para los demás.)
create or replace function public.my_private_profile()
returns json
language sql
stable
security definer
set search_path to 'public'
as $$
  select json_build_object(
    'emergency_contact_name', p.emergency_contact_name,
    'emergency_contact_phone', p.emergency_contact_phone
  )
  from public.profiles p
  where p.id = auth.uid();
$$;
revoke all on function public.my_private_profile() from public, anon;
grant execute on function public.my_private_profile() to authenticated;

-- 2) Votos de alertas: una sola función que solo cambia los contadores.
--    p_action: 'up' | 'down' | 'remove_up' | 'remove_down'
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

  update public.bike_alerts
     set voters_up   = v_up,
         voters_down = v_down,
         votes_up    = jsonb_array_length(v_up),
         votes_down  = jsonb_array_length(v_down)
   where id = p_alert;

  return json_build_object(
    'changed', v_changed,
    'votes_up', jsonb_array_length(v_up),
    'votes_down', jsonb_array_length(v_down)
  );
end;
$$;
revoke all on function public.vote_alert(uuid, text) from public, anon;
grant execute on function public.vote_alert(uuid, text) to authenticated;

-- 3) Al crear una alerta, el servidor fija autor, nombre visible y votos en
--    cero (antes la app podía crearla con votos o con otro nombre).
create or replace function public.bike_alerts_before_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_name text;
begin
  if public.is_trusted_writer() then
    return new;
  end if;
  select coalesce(nullif(trim(username), ''), nullif(trim(full_name), ''), 'Ciclista')
    into v_name
    from public.profiles where id = new.user_id;
  new.user_name   := coalesce(v_name, new.user_name, 'Ciclista');
  new.votes_up    := 0;
  new.votes_down  := 0;
  new.voters_up   := '[]'::jsonb;
  new.voters_down := '[]'::jsonb;
  new.is_active   := true;
  new.created_at  := now();
  return new;
end;
$$;
drop trigger if exists bike_alerts_before_insert on public.bike_alerts;
create trigger bike_alerts_before_insert
  before insert on public.bike_alerts
  for each row execute function public.bike_alerts_before_insert();

-- 4) Estadísticas diarias con límites realistas (antes aceptaba cualquier
--    cantidad de km y velocidad).
create or replace function public.bump_ride_stats(p_day date, p_km numeric, p_max_speed numeric default 0)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_km    numeric := least(greatest(coalesce(p_km, 0), 0), 50);         -- por envío
  v_speed numeric := least(greatest(coalesce(p_max_speed, 0), 0), 90);  -- km/h
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  -- Solo hoy o ayer (zona horaria de Chile): no se pueden rellenar días pasados.
  if p_day is null
     or p_day > (now() at time zone 'America/Santiago')::date
     or p_day < (now() at time zone 'America/Santiago')::date - 1 then
    return;
  end if;

  insert into public.ride_stats (user_id, day, km, max_speed_kmh, updated_at)
  values (auth.uid(), p_day, v_km, v_speed, now())
  on conflict (user_id, day) do update
    set km            = least(public.ride_stats.km + v_km, 400),        -- tope diario
        max_speed_kmh = greatest(public.ride_stats.max_speed_kmh, v_speed),
        updated_at    = now();
end;
$$;

-- 5) Contraseña de eventos privados: se guarda en una tabla aparte que nadie
--    puede leer desde la app; la columna events.password_hash queda vacía.
--    (Ocultar la columna no sirve: la app escucha los eventos en tiempo real
--    pidiendo todas las columnas y dejaría de cargarlos.)
create table if not exists public.event_secrets (
  event_id      uuid primary key
                references public.events(id) on delete cascade
                deferrable initially deferred,
  password_hash text not null
);
alter table public.event_secrets enable row level security;
revoke all on public.event_secrets from anon, authenticated;

insert into public.event_secrets (event_id, password_hash)
select id, password_hash from public.events where password_hash is not null
on conflict (event_id) do update set password_hash = excluded.password_hash;
update public.events set password_hash = null where password_hash is not null;

create or replace function public.events_move_secret()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.password_hash is not null then
    insert into public.event_secrets (event_id, password_hash)
    values (new.id, new.password_hash)
    on conflict (event_id) do update set password_hash = excluded.password_hash;
    new.password_hash := null;
  end if;
  return new;
end;
$$;
drop trigger if exists events_move_secret on public.events;
create trigger events_move_secret
  before insert or update on public.events
  for each row execute function public.events_move_secret();

-- join_event compara contra la tabla de secretos.
create or replace function public.join_event(p_event_id uuid, p_password_hash text default null)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_ev public.events%rowtype;
  v_hash text;
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
    select password_hash into v_hash from public.event_secrets where event_id = p_event_id;
    if v_hash is null
       or p_password_hash is null
       or lower(p_password_hash) <> lower(v_hash) then
      return 'wrong_password';
    end if;
  end if;

  if v_ev.max_participants is not null
     and jsonb_array_length(v_ids) >= v_ev.max_participants then
    return 'full';
  end if;

  v_ids := v_ids || jsonb_build_array(v_uid::text);
  update public.events
     set participants_ids = v_ids,
         participants_count = jsonb_array_length(v_ids)
   where id = p_event_id;
  return 'ok';
end;
$$;
revoke all on function public.join_event(uuid, text) from public, anon;
grant execute on function public.join_event(uuid, text) to authenticated;
