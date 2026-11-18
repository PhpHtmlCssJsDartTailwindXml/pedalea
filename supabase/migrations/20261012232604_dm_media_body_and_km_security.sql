-- Corrige el envío de fotos/audios/eliminar en mensajes y asegura los km.
-- Aplicar en Supabase → SQL Editor (proyecto ocheyavlacprkvbongno). Es idempotente.

-- 1) Fotos sin comentario, audios y mensajes eliminados llevan body vacío;
--    la regla anterior exigía al menos 1 carácter y rechazaba los tres.
alter table public.dm_messages drop constraint if exists dm_messages_body_check;
alter table public.dm_messages add constraint dm_messages_body_check check (
  char_length(body) <= 2000
  and (char_length(body) >= 1 or kind <> 'text' or deleted_at is not null)
);

-- 2) increment_total_km: antes cualquier usuario podía cambiar los km de
--    cualquier otro (incluso restar). Ahora solo los propios, solo sumar y
--    con un tope de 50 km por llamada (la app envía tramos de ~0,2 km).
create or replace function public.increment_total_km(uid uuid, km_delta numeric)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_me uuid := (select auth.uid());
begin
  if v_me is null or uid is distinct from v_me then
    raise exception 'not_allowed';
  end if;
  if km_delta is null or km_delta <= 0 then
    return;
  end if;
  update public.profiles
     set total_km = coalesce(total_km, 0) + least(km_delta, 50)
   where id = v_me;
end;
$$;
revoke all on function public.increment_total_km(uuid, numeric) from public, anon;
grant execute on function public.increment_total_km(uuid, numeric) to authenticated;

-- 3) total_km solo cambia vía increment_total_km (o el servidor), no con un
--    update directo desde la app (mismo patrón que protect_is_plus).
create or replace function public.protect_total_km()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if public.is_trusted_writer() then
    return new;
  end if;
  new.total_km := old.total_km;
  return new;
end;
$$;

drop trigger if exists profiles_protect_total_km on public.profiles;
create trigger profiles_protect_total_km
  before update on public.profiles
  for each row execute function public.protect_total_km();
