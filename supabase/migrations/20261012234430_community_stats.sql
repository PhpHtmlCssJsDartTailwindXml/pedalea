-- Totales públicos de la comunidad para la pantalla de login (sin datos
-- personales: solo agregados). Ya aplicada en el proyecto ocheyavlacprkvbongno.
create or replace function public.community_stats()
returns json
language sql
stable
security definer
set search_path to 'public'
as $$
  select json_build_object(
    'cyclists', (select count(*) from public.profiles),
    'total_km', (select coalesce(round(sum(total_km)::numeric, 1), 0) from public.profiles),
    'alerts',   (select count(*) from public.bike_alerts)
  );
$$;
revoke all on function public.community_stats() from public;
grant execute on function public.community_stats() to anon, authenticated;
