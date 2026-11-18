-- Dos funciones nuevas:
--   1. "Mis bicis": cada ciclista registra sus bicis, la app suma los km a la
--      bici activa y avisa cuando toca mantención.
--   2. "Tu aporte ayudó a…": se cuenta cuántos ciclistas distintos vieron
--      cada alerta y se avisa al autor al llegar a ciertos hitos.
--
-- Pegar completo en Supabase → SQL Editor → Run. Se puede ejecutar más de
-- una vez sin romper nada.

-- ═══════════════════════════════════════════════════════════════════════
-- 1. MIS BICIS
-- ═══════════════════════════════════════════════════════════════════════

create table if not exists public.bikes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 40),
  type        text not null default 'urbana'
                check (type in ('ruta', 'urbana', 'montana', 'electrica', 'otra')),
  photo_url   text,
  base_km     numeric(10, 2) not null default 0 check (base_km between 0 and 200000),
  app_km      numeric(10, 2) not null default 0 check (app_km >= 0),
  is_active   boolean not null default false,
  created_at  timestamptz not null default now()
);

create index if not exists bikes_user_idx on public.bikes (user_id);

-- Una sola bici activa por persona.
create unique index if not exists bikes_one_active_per_user
  on public.bikes (user_id) where is_active;

alter table public.bikes enable row level security;

drop policy if exists bikes_owner_all on public.bikes;
create policy bikes_owner_all on public.bikes
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Mantenciones por bici: cada fila es un tipo (lubricar cadena, frenos…)
-- con su intervalo en km y el odómetro de la bici la última vez que se hizo.
create table if not exists public.bike_maintenance (
  id            uuid primary key default gen_random_uuid(),
  bike_id       uuid not null references public.bikes (id) on delete cascade,
  user_id       uuid not null default auth.uid()
                  references auth.users (id) on delete cascade,
  kind          text not null check (kind in ('lube', 'brakes', 'chain', 'tires')),
  interval_km   numeric(10, 2) not null check (interval_km between 50 and 50000),
  last_done_km  numeric(10, 2) not null default 0,
  last_done_at  timestamptz,
  notified      boolean not null default false,
  unique (bike_id, kind)
);

create index if not exists bike_maintenance_bike_idx on public.bike_maintenance (bike_id);

alter table public.bike_maintenance enable row level security;

drop policy if exists bike_maintenance_owner_all on public.bike_maintenance;
create policy bike_maintenance_owner_all on public.bike_maintenance
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Plan gratis: 1 bici. Pedalea Plus: ilimitadas. La primera bici queda
-- activa sola.
create or replace function public.bikes_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_plus  boolean;
begin
  select count(*) into v_count from public.bikes where user_id = new.user_id;
  select coalesce(is_plus, false) into v_plus from public.profiles where id = new.user_id;
  if v_count >= 1 and not coalesce(v_plus, false) then
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

drop trigger if exists bikes_before_insert on public.bikes;
create trigger bikes_before_insert
  before insert on public.bikes
  for each row execute function public.bikes_before_insert();

-- Al crear una bici se crean sus 4 mantenciones con intervalos de
-- referencia (el ciclista los puede cambiar). Se cuenta desde hoy.
create or replace function public.bikes_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.bike_maintenance (bike_id, user_id, kind, interval_km, last_done_km)
  values
    (new.id, new.user_id, 'lube',   300,  new.base_km),
    (new.id, new.user_id, 'brakes', 1000, new.base_km),
    (new.id, new.user_id, 'chain',  1500, new.base_km),
    (new.id, new.user_id, 'tires',  3000, new.base_km)
  on conflict (bike_id, kind) do nothing;
  return new;
end;
$$;

drop trigger if exists bikes_after_insert on public.bikes;
create trigger bikes_after_insert
  after insert on public.bikes
  for each row execute function public.bikes_after_insert();

-- Los km de la app no se pueden editar a mano (solo con add_bike_km).
create or replace function public.bikes_protect_app_km()
returns trigger
language plpgsql
as $$
begin
  if new.app_km is distinct from old.app_km
     and current_setting('pedalea.bike_km', true) is distinct from 'on' then
    new.app_km := old.app_km;
  end if;
  return new;
end;
$$;

drop trigger if exists bikes_protect_app_km on public.bikes;
create trigger bikes_protect_app_km
  before update on public.bikes
  for each row execute function public.bikes_protect_app_km();

-- Elige la bici activa (la que suma los km).
create or replace function public.set_active_bike(p_bike uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.bikes where id = p_bike and user_id = auth.uid()) then
    raise exception 'bike_not_found';
  end if;
  update public.bikes set is_active = false where user_id = auth.uid() and is_active;
  update public.bikes set is_active = true where id = p_bike;
end;
$$;

-- Suma km a la bici activa y devuelve las mantenciones que se acaban de
-- cumplir (cada una se avisa una sola vez por ciclo).
create or replace function public.add_bike_km(p_km numeric)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bike public.bikes;
  v_odo  numeric;
  v_due  json;
begin
  if auth.uid() is null or p_km is null or p_km <= 0 or p_km > 5 then
    return null;
  end if;

  perform set_config('pedalea.bike_km', 'on', true);
  update public.bikes
     set app_km = app_km + p_km
   where user_id = auth.uid() and is_active
  returning * into v_bike;
  perform set_config('pedalea.bike_km', 'off', true);

  if v_bike.id is null then
    return null; -- sin bici registrada
  end if;
  v_odo := v_bike.base_km + v_bike.app_km;

  with due as (
    update public.bike_maintenance m
       set notified = true
     where m.bike_id = v_bike.id
       and not m.notified
       and v_odo - m.last_done_km >= m.interval_km
    returning m.kind, m.interval_km
  )
  select coalesce(json_agg(json_build_object('kind', kind, 'interval_km', interval_km)), '[]'::json)
    into v_due from due;

  return json_build_object(
    'bike_id', v_bike.id,
    'name', v_bike.name,
    'odometer', v_odo,
    'due', v_due
  );
end;
$$;

-- Marca una mantención como hecha: el contador vuelve a cero.
create or replace function public.mark_maintenance_done(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.bike_maintenance m
     set last_done_km = b.base_km + b.app_km,
         last_done_at = now(),
         notified = false
    from public.bikes b
   where m.id = p_id
     and b.id = m.bike_id
     and m.user_id = auth.uid();
end;
$$;

revoke all on function public.set_active_bike(uuid) from public;
revoke all on function public.add_bike_km(numeric) from public;
revoke all on function public.mark_maintenance_done(uuid) from public;
grant execute on function public.set_active_bike(uuid) to authenticated;
grant execute on function public.add_bike_km(numeric) to authenticated;
grant execute on function public.mark_maintenance_done(uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 2. "TU APORTE AYUDÓ A…"
-- ═══════════════════════════════════════════════════════════════════════

-- Un registro por ciclista y alerta (se cuenta una sola vez por persona).
-- Nadie puede leer esta tabla directamente: el autor solo ve totales.
create table if not exists public.alert_views (
  alert_id   uuid not null references public.bike_alerts (id) on delete cascade,
  viewer_id  uuid not null references auth.users (id) on delete cascade,
  kind       text not null check (kind in ('open', 'nearby')),
  created_at timestamptz not null default now(),
  primary key (alert_id, viewer_id)
);

create index if not exists alert_views_created_idx on public.alert_views (created_at);

alter table public.alert_views enable row level security;

-- Registra que el ciclista vio una alerta (la abrió o pasó cerca) y, si se
-- llega a un hito, avisa al autor por push.
create or replace function public.register_alert_view(p_alert uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_author uuid;
  v_type   text;
  v_place  text;
  v_rows   int;
  v_count  int;
  v_secret text;
begin
  if auth.uid() is null or p_kind not in ('open', 'nearby') then
    return;
  end if;

  select user_id, type, coalesce(nullif(location_name, ''), title)
    into v_author, v_type, v_place
    from public.bike_alerts where id = p_alert;
  if v_author is null or v_author = auth.uid() then
    return; -- alerta inexistente o propia: no cuenta
  end if;

  insert into public.alert_views (alert_id, viewer_id, kind)
  values (p_alert, auth.uid(), p_kind)
  on conflict (alert_id, viewer_id) do nothing;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return; -- ya la había visto
  end if;

  select count(*) into v_count from public.alert_views where alert_id = p_alert;
  if v_count not in (3, 10, 25, 50, 100, 250, 500) then
    return;
  end if;

  begin
    select decrypted_secret into v_secret
      from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;
    if v_secret is not null then
      perform net.http_post(
        url := 'https://ocheyavlacprkvbongno.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-push-secret', v_secret
        ),
        body := jsonb_build_object(
          'table', 'alert_milestone',
          'op', 'INSERT',
          'record', jsonb_build_object(
            'author_id', v_author,
            'alert_id', p_alert,
            'count', v_count,
            'type', v_type,
            'place', v_place
          )
        ),
        timeout_milliseconds := 5000
      );
    end if;
  exception when others then
    null; -- el aviso nunca impide registrar la vista
  end;
end;
$$;

-- Totales del usuario actual: a cuántos ciclistas distintos ayudaron sus
-- alertas (en total y en los últimos 7 días) y cuántas alertas sirvieron.
create or replace function public.my_alert_impact()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'total', count(distinct v.viewer_id),
    'week', count(distinct v.viewer_id) filter (where v.created_at > now() - interval '7 days'),
    'alerts', count(distinct v.alert_id)
  )
  from public.alert_views v
  join public.bike_alerts a on a.id = v.alert_id
  where a.user_id = auth.uid();
$$;

revoke all on function public.register_alert_view(uuid, text) from public;
revoke all on function public.my_alert_impact() from public;
grant execute on function public.register_alert_view(uuid, text) to authenticated;
grant execute on function public.my_alert_impact() to authenticated;
