-- EJECUTAR MÁS ADELANTE, cuando casi todos los usuarios tengan la versión
-- 1.3.1 (29) o superior. Las versiones anteriores leen events con select *
-- y dejarían de ver los eventos si esta columna se oculta antes.

-- 4e. Ocultar el hash de la contraseña de los eventos privados.
revoke select on public.events from anon, authenticated;
grant select (id, user_id, created_by, title, description, event_date,
              location_name, latitude, longitude, max_participants,
              participants_count, participants_ids, is_active, created_at,
              is_private)
  on public.events to anon, authenticated;
