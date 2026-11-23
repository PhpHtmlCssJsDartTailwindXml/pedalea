-- Velocidad máxima realista para bicicleta.
--
-- Problema: la app aceptaba como velocidad máxima un dato suelto del GPS de
-- hasta 80 km/h y el servidor hasta 90 km/h. Muchos usuarios quedaron con
-- 70-80 km/h de tramos hechos en auto, micro o metro.
--
-- Desde la versión 1.4.1 la app solo suma km y velocidad de bloques que
-- parecen pedaleo (PedalFilter) y la velocidad es la sostenida, no un dato
-- suelto. Esta migración pone el mismo criterio en el servidor y limpia lo
-- que ya estaba inflado.

-- 1) Tope de 60 km/h al guardar (antes 90). Una velocidad mayor no es de bici:
--    no se guarda (los km del envío sí, la app ya los filtró).
create or replace function public.bump_ride_stats(p_day date, p_km numeric, p_max_speed numeric default 0)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_km    numeric := least(greatest(coalesce(p_km, 0), 0), 50);   -- por envío
  v_speed numeric := greatest(coalesce(p_max_speed, 0), 0);        -- km/h
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
  if v_speed > 60 then
    v_speed := 0;
  end if;

  insert into public.ride_stats (user_id, day, km, max_speed_kmh, updated_at)
  values (auth.uid(), p_day, v_km, v_speed, now())
  on conflict (user_id, day) do update
    set km            = least(public.ride_stats.km + v_km, 400),        -- tope diario
        max_speed_kmh = greatest(public.ride_stats.max_speed_kmh, v_speed),
        updated_at    = now();
end;
$$;

-- 2) Ranking de velocidad: ignora cualquier valor sobre 60 km/h que pudiera
--    quedar (misma salida que antes).
create or replace function public.ride_ranking(p_metric text, p_since date, p_limit integer default 50)
returns table(user_id uuid, username text, avatar_url text, value numeric)
language sql
stable
security definer
set search_path to 'public'
as $$
  select rs.user_id,
         coalesce(nullif(trim(p.username), ''), nullif(trim(p.full_name), ''), 'Ciclista') as username,
         p.avatar_url,
         case when p_metric = 'max_speed'
              then max(case when rs.max_speed_kmh <= 60 then rs.max_speed_kmh else 0 end)
              else sum(rs.km) end as value
  from public.ride_stats rs
  join public.profiles p on p.id = rs.user_id
  where rs.day >= p_since
  group by rs.user_id, p.username, p.full_name, p.avatar_url
  having (case when p_metric = 'max_speed'
               then max(case when rs.max_speed_kmh <= 60 then rs.max_speed_kmh else 0 end)
               else sum(rs.km) end) > 0
  order by value desc
  limit least(coalesce(p_limit, 50), 200);
$$;

-- 3) Limpieza: las velocidades sobre 40 km/h se midieron con el método
--    anterior (un dato suelto del GPS, sin filtrar vehículos) y no son
--    confiables. Se dejan en 0 ("sin dato"); la app las vuelve a medir con el
--    filtro nuevo. Los km de esos días no se tocan.
update public.ride_stats
   set max_speed_kmh = 0
 where max_speed_kmh > 40
   and day < date '2026-11-24';
