-- Avisos para que los ciclistas vuelvan a la app (versión 1.4.2).
--
-- 1) Logro «Primer pedaleo»: se desbloquea con el primer kilómetro.
-- 2) Resumen semanal: lunes 8:00, a quien pedaleó la semana anterior
--    (km, días, CO2 evitado y su puesto en la comuna).
-- 3) Aviso de racha: todos los días a las 18:00, solo a quien lleva 3 o más
--    días seguidos y hoy todavía no pedalea.
--
-- Los avisos los envía la Edge Function send-push (tipo «personal»: cada
-- elemento trae su destinatario y su texto). Se programan con pg_cron.
-- pg_cron usa la hora UTC: 11:00 y 21:00 UTC son las 8:00 y las 18:00 en el
-- horario de verano de Chile (en invierno llegan una hora antes).

-- 1) Logro ---------------------------------------------------------------------
insert into public.achievements (id, category, requirement_value, title, description, icon)
values ('first_ride', 'kilometros', 1, 'Primer pedaleo', 'Recorre tu primer kilómetro con Pedalea.', '🚲')
on conflict (id) do nothing;

-- 2) Envío en lote a send-push -------------------------------------------------
create or replace function public.push_personal(p_type text, p_payload text, p_store boolean, p_items jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_secret text;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    return null;
  end if;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;
  if v_secret is null then
    return null;
  end if;
  return net.http_post(
    url := 'https://ocheyavlacprkvbongno.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    body := jsonb_build_object(
      'table', 'personal',
      'op', 'INSERT',
      'record', jsonb_build_object('type', p_type, 'payload', p_payload, 'store', p_store, 'items', p_items)
    ),
    timeout_milliseconds := 120000
  );
end;
$$;
revoke all on function public.push_personal(text, text, boolean, jsonb) from public, anon, authenticated;

-- km con coma decimal y 1 decimal (12,3)
create or replace function public.fmt_km(p numeric)
returns text
language sql
immutable
as $$ select replace(to_char(round(coalesce(p, 0), 1), 'FM999990.0'), '.', ',') $$;

-- 3) Resumen semanal -----------------------------------------------------------
create or replace function public.weekly_summary_push()
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_today date := (now() at time zone 'America/Santiago')::date;
  v_from  date := date_trunc('week', v_today)::date - 7;  -- lunes de la semana pasada
  v_to    date := date_trunc('week', v_today)::date - 1;  -- domingo de la semana pasada
  v_items jsonb;
begin
  with wk as (
    select rs.user_id, sum(rs.km) as km, count(*) filter (where rs.km > 0.1) as dias
      from public.ride_stats rs
     where rs.day between v_from and v_to
     group by rs.user_id
    having sum(rs.km) >= 0.5
  ), ranked as (
    select wk.*, nullif(trim(p.commune), '') as commune,
           rank()   over (partition by nullif(trim(p.commune), '') order by wk.km desc) as pos,
           count(*) over (partition by nullif(trim(p.commune), '')) as n
      from wk join public.profiles p on p.id = wk.user_id
  )
  select jsonb_agg(jsonb_build_object(
           'user_id', r.user_id,
           'title', 'Tu semana en bici: ' || public.fmt_km(r.km) || ' km 🚴',
           'body', r.dias || case when r.dias = 1 then ' día' else ' días' end
                   || ' pedaleando y ' || public.fmt_km(r.km * 0.13) || ' kg de CO₂ evitados.'
                   || case when r.commune is not null and r.n >= 3
                           then ' Quedaste #' || r.pos || ' en ' || r.commune || '.' else '' end
                   || ' Toca para ver tus estadísticas.'))
    into v_items
    from ranked r
   where exists (select 1 from public.device_tokens d where d.user_id = r.user_id);

  return public.push_personal('weekly_summary', 'my_stats', true, v_items);
end;
$$;
revoke all on function public.weekly_summary_push() from public, anon, authenticated;

-- 4) Aviso de racha -------------------------------------------------------------
create or replace function public.streak_reminder_push()
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_today date := (now() at time zone 'America/Santiago')::date;
  v_items jsonb;
begin
  with d as (
    select user_id, day
      from public.ride_stats
     where km > 0.1 and day < v_today and day >= v_today - 400
  ), g as (
    select user_id, day, day - (row_number() over (partition by user_id order by day))::int as grp
      from d
  ), s as (
    select user_id, count(*) as len, max(day) as last_day
      from g group by user_id, grp
  )
  select jsonb_agg(jsonb_build_object(
           'user_id', s.user_id,
           'title', '🔥 Llevas ' || s.len || ' días seguidos',
           'body', 'Sal a pedalear hoy para no perder tu racha. ¡Tú puedes!'))
    into v_items
    from s
   where s.last_day = v_today - 1
     and s.len >= 3
     and not exists (select 1 from public.ride_stats t
                      where t.user_id = s.user_id and t.day = v_today and t.km > 0.1)
     and exists (select 1 from public.device_tokens dt where dt.user_id = s.user_id);

  return public.push_personal('streak_reminder', 'my_stats', false, v_items);
end;
$$;
revoke all on function public.streak_reminder_push() from public, anon, authenticated;

-- 5) Programación ---------------------------------------------------------------
create extension if not exists pg_cron;

select cron.unschedule(jobid) from cron.job
 where jobname in ('pedalea_weekly_summary', 'pedalea_streak_reminder');

select cron.schedule('pedalea_weekly_summary', '0 11 * * 1', $$select public.weekly_summary_push()$$);
select cron.schedule('pedalea_streak_reminder', '0 21 * * *', $$select public.streak_reminder_push()$$);
