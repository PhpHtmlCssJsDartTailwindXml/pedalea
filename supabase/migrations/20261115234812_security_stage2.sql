-- SEGURIDAD · ETAPA 2 (ejecutar UNOS DÍAS DESPUÉS de publicar la 1.3.3,
-- cuando en Play Console casi todos los usuarios estén en la 1.3.3 o superior)
--
-- Cierra los accesos que la app antigua usaba directamente. Las versiones
-- anteriores a la 1.3.3 dejarán de poder votar alertas hasta actualizar
-- (la actualización obligatoria de Play las lleva a hacerlo al abrir la app).
-- Requiere haber ejecutado antes 20261115234811_security_stage1.sql.

-- 1) Contactos de emergencia: dejan de ser legibles para los demás usuarios.
--    Cada usuario lee los suyos con my_private_profile().
revoke select on public.profiles from anon, authenticated;
grant select (id, username, full_name, avatar_url, commune, total_km, created_at,
              fall_detection_enabled, is_plus, plus_badge_variant,
              stats_accent_index, map_style)
  on public.profiles to anon, authenticated;

-- 2) Alertas: solo el autor modifica su alerta, y los votos solo cambian con
--    vote_alert() (el autor tampoco puede inflar sus propios votos).
drop policy if exists bike_alerts_update_authenticated on public.bike_alerts;
drop policy if exists bike_alerts_update_own on public.bike_alerts;
create policy bike_alerts_update_own on public.bike_alerts
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function public.bike_alerts_protect()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if public.is_trusted_writer() then
    return new;
  end if;
  new.user_id     := old.user_id;
  new.user_name   := old.user_name;
  new.votes_up    := old.votes_up;
  new.votes_down  := old.votes_down;
  new.voters_up   := old.voters_up;
  new.voters_down := old.voters_down;
  new.created_at  := old.created_at;
  return new;
end;
$$;
drop trigger if exists bike_alerts_protect on public.bike_alerts;
create trigger bike_alerts_protect
  before update on public.bike_alerts
  for each row execute function public.bike_alerts_protect();

-- 3) Estadísticas diarias: solo se escriben con bump_ride_stats() (con límites).
drop policy if exists ride_stats_insert_own on public.ride_stats;
drop policy if exists ride_stats_update_own on public.ride_stats;

-- 4) Fotos: cada usuario solo sube a su propia carpeta (las fotos de perfil
--    usan avatars/<id>_<fecha>.jpg y siguen permitidas).
drop policy if exists alert_photos_authenticated_insert on storage.objects;
create policy alert_photos_authenticated_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'alert-photos' and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or name like 'avatars/' || (select auth.uid())::text || '\_%'
    )
  );
drop policy if exists poi_photos_authenticated_insert on storage.objects;
create policy poi_photos_authenticated_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'poi-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists event_photos_authenticated_insert on storage.objects;
create policy event_photos_authenticated_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'event-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists post_images_auth_insert on storage.objects;
create policy post_images_auth_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'post-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
