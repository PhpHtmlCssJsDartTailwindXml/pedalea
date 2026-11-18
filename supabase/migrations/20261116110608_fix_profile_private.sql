-- ARREGLO: "permission denied for table profiles" al guardar el perfil.
--
-- La etapa 2 ocultó las columnas del contacto de emergencia con permisos por
-- columna, pero la app guarda el perfil con upsert (INSERT ... ON CONFLICT DO
-- UPDATE), que exige poder leer la tabla completa. Solución: el contacto de
-- emergencia se guarda en una tabla privada aparte y la tabla profiles vuelve
-- a ser legible (esas dos columnas quedan siempre vacías).

-- 1) Tabla privada: solo se accede con funciones del servidor.
create table if not exists public.profile_private (
  user_id                 uuid primary key
                          references public.profiles(id) on delete cascade
                          deferrable initially deferred,
  emergency_contact_name  text,
  emergency_contact_phone text,
  updated_at              timestamptz not null default now()
);
alter table public.profile_private enable row level security;
revoke all on public.profile_private from anon, authenticated;

-- 2) Mover los contactos actuales y vaciar las columnas públicas.
insert into public.profile_private (user_id, emergency_contact_name, emergency_contact_phone)
select id, emergency_contact_name, emergency_contact_phone
  from public.profiles
 where emergency_contact_name is not null or emergency_contact_phone is not null
on conflict (user_id) do update
  set emergency_contact_name  = excluded.emergency_contact_name,
      emergency_contact_phone = excluded.emergency_contact_phone,
      updated_at = now();
update public.profiles
   set emergency_contact_name = null, emergency_contact_phone = null
 where emergency_contact_name is not null or emergency_contact_phone is not null;

-- 3) Cada vez que la app guarda el contacto en profiles, se mueve a la tabla
--    privada. Un texto vacío ('') significa "borrar el contacto"; null significa
--    "no lo estoy cambiando" (por ejemplo, al cambiar solo la foto).
create or replace function public.profiles_move_private()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.emergency_contact_name is not null or new.emergency_contact_phone is not null then
    insert into public.profile_private (user_id, emergency_contact_name, emergency_contact_phone)
    values (new.id,
            nullif(trim(new.emergency_contact_name), ''),
            nullif(trim(new.emergency_contact_phone), ''))
    on conflict (user_id) do update
      set emergency_contact_name  = case when new.emergency_contact_name is null
                                         then public.profile_private.emergency_contact_name
                                         else nullif(trim(new.emergency_contact_name), '') end,
          emergency_contact_phone = case when new.emergency_contact_phone is null
                                         then public.profile_private.emergency_contact_phone
                                         else nullif(trim(new.emergency_contact_phone), '') end,
          updated_at = now();
  end if;
  new.emergency_contact_name  := null;
  new.emergency_contact_phone := null;
  return new;
end;
$$;
drop trigger if exists profiles_move_private on public.profiles;
create trigger profiles_move_private
  before insert or update on public.profiles
  for each row execute function public.profiles_move_private();

-- 4) El dueño lee su contacto desde la tabla privada.
create or replace function public.my_private_profile()
returns json
language sql
stable
security definer
set search_path to 'public'
as $$
  select json_build_object(
    'emergency_contact_name', pp.emergency_contact_name,
    'emergency_contact_phone', pp.emergency_contact_phone
  )
  from (select auth.uid() as uid) me
  left join public.profile_private pp on pp.user_id = me.uid;
$$;
revoke all on function public.my_private_profile() from public, anon;
grant execute on function public.my_private_profile() to authenticated;

-- 5) La tabla profiles vuelve a ser legible completa (ya no guarda datos privados).
grant select on public.profiles to anon, authenticated;
