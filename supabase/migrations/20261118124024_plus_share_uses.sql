-- Imágenes «Plus» gratis al compartir estadísticas.
--
-- Quien no es Plus puede exportar (compartir o descargar) hasta 2 imágenes
-- por semana con funciones Plus: foto de fondo, sin fondo o colores Plus.
-- La semana va de lunes a domingo, hora de Chile. Quien es Plus no tiene
-- límite. El conteo vive en el servidor para que no se reinicie al
-- reinstalar la app. La app no escribe la tabla: todo pasa por las funciones.

create table if not exists public.plus_share_uses (
  id      bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  used_at timestamptz not null default now()
);

create index if not exists plus_share_uses_user_time
  on public.plus_share_uses (user_id, used_at desc);

alter table public.plus_share_uses enable row level security;
revoke all on public.plus_share_uses from anon, authenticated;

-- Límite semanal (un solo lugar para cambiarlo).
create or replace function public.plus_share_weekly_limit()
returns int language sql immutable as $$ select 2 $$;

-- Cuántas imágenes Plus gratis le quedan esta semana al usuario.
-- Devuelve -1 si es Plus (sin límite).
create or replace function public.plus_share_remaining()
returns int
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_used int;
begin
  if v_uid is null then
    return 0;
  end if;
  if exists (select 1 from public.profiles where id = v_uid and is_plus) then
    return -1;
  end if;
  select count(*) into v_used
    from public.plus_share_uses
   where user_id = v_uid
     and used_at >= (date_trunc('week', now() at time zone 'America/Santiago') at time zone 'America/Santiago');
  return greatest(public.plus_share_weekly_limit() - v_used, 0);
end;
$$;

-- Usa una imagen Plus gratis. Devuelve cuántas quedan después de usarla,
-- -1 si es Plus, o null si ya no le quedaban (no se registra nada).
create or replace function public.use_plus_share()
returns int
language plpgsql
volatile
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_left int;
begin
  if v_uid is null then
    return null;
  end if;
  -- Evita que dos llamadas simultáneas se salten el límite.
  perform pg_advisory_xact_lock(hashtext('plus_share:' || v_uid::text));
  v_left := public.plus_share_remaining();
  if v_left = -1 then
    return -1;
  end if;
  if v_left <= 0 then
    return null;
  end if;
  insert into public.plus_share_uses (user_id) values (v_uid);
  return v_left - 1;
end;
$$;

revoke all on function public.plus_share_remaining() from public, anon;
revoke all on function public.use_plus_share() from public, anon;
grant execute on function public.plus_share_remaining() to authenticated;
grant execute on function public.use_plus_share() to authenticated;
