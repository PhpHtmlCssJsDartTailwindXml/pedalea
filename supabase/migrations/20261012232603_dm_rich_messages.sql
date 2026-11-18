-- Mensajes directos enriquecidos: fotos, audios, responder y eliminar para todos.
-- Aplicar en Supabase → SQL Editor (proyecto ocheyavlacprkvbongno). Es idempotente.

alter table public.dm_messages
  add column if not exists kind text not null default 'text',
  add column if not exists media_path text,
  add column if not exists media_duration_ms integer,
  add column if not exists reply_to uuid references public.dm_messages(id) on delete set null,
  add column if not exists deleted_at timestamptz;

alter table public.dm_messages
  drop constraint if exists dm_messages_kind_check;
alter table public.dm_messages
  add constraint dm_messages_kind_check check (kind in ('text','image','audio'));

create index if not exists dm_messages_thread_created_idx
  on public.dm_messages (thread_id, created_at);
create index if not exists dm_messages_recipient_unread_idx
  on public.dm_messages (recipient_id) where read_at is null;

-- El destinatario solo puede marcar como leído (antes podía cambiar cualquier columna).
revoke update on public.dm_messages from anon, authenticated;
grant update (read_at) on public.dm_messages to authenticated;
revoke insert, delete, truncate on public.dm_messages from anon, authenticated;
revoke insert, update, delete, truncate on public.dm_threads from anon, authenticated;

-- Crea (o devuelve) el hilo con otra persona, validando que puedan escribirse.
create or replace function public.dm_ensure_thread(p_recipient uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_me uuid := (select auth.uid());
  v_tid uuid;
begin
  if v_me is null then raise exception 'unauthorized'; end if;
  if not public.dm_allowed(v_me, p_recipient) then raise exception 'not_allowed'; end if;
  insert into public.dm_threads (user_a, user_b)
  values (least(v_me, p_recipient), greatest(v_me, p_recipient))
  on conflict (user_a, user_b) do update set user_a = excluded.user_a
  returning id into v_tid;
  return v_tid;
end;
$$;

drop function if exists public.dm_send(uuid, text);

create or replace function public.dm_send(
  p_recipient uuid,
  p_body text default '',
  p_kind text default 'text',
  p_media_path text default null,
  p_media_duration_ms integer default null,
  p_reply_to uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_me  uuid := (select auth.uid());
  v_tid uuid;
  v_preview text;
begin
  if v_me is null then raise exception 'unauthorized'; end if;
  p_body := btrim(coalesce(p_body, ''));
  p_kind := coalesce(p_kind, 'text');
  if p_kind not in ('text','image','audio') then raise exception 'invalid_kind'; end if;
  if char_length(p_body) > 2000 then raise exception 'invalid_body'; end if;
  if p_kind = 'text' and p_body = '' then raise exception 'invalid_body'; end if;
  if not public.dm_allowed(v_me, p_recipient) then raise exception 'not_allowed'; end if;

  v_tid := public.dm_ensure_thread(p_recipient);

  if p_kind <> 'text' then
    -- El archivo debe estar en la carpeta del hilo y del remitente.
    if p_media_path is null
       or p_media_path not like v_tid::text || '/' || v_me::text || '/%' then
      raise exception 'invalid_media';
    end if;
  else
    p_media_path := null;
    p_media_duration_ms := null;
  end if;

  if p_reply_to is not null and not exists (
    select 1 from public.dm_messages where id = p_reply_to and thread_id = v_tid
  ) then
    p_reply_to := null;
  end if;

  insert into public.dm_messages
    (thread_id, sender_id, recipient_id, body, kind, media_path, media_duration_ms, reply_to)
  values
    (v_tid, v_me, p_recipient, p_body, p_kind, p_media_path, p_media_duration_ms, p_reply_to);

  v_preview := case p_kind
    when 'image' then '📷 Foto' || case when p_body <> '' then ' · ' || p_body else '' end
    when 'audio' then '🎤 Mensaje de voz'
    else p_body end;

  update public.dm_threads
     set last_body = v_preview, last_at = now(), last_sender = v_me
   where id = v_tid;

  return v_tid;
end;
$$;

-- Eliminar para todos: solo quien lo envió. Devuelve la ruta del archivo
-- (si tenía) para que el cliente lo borre del storage.
create or replace function public.dm_delete(p_message uuid)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_me uuid := (select auth.uid());
  v_msg public.dm_messages%rowtype;
  v_last uuid;
begin
  if v_me is null then raise exception 'unauthorized'; end if;
  select * into v_msg from public.dm_messages where id = p_message;
  if not found or v_msg.sender_id <> v_me then raise exception 'not_allowed'; end if;
  if v_msg.deleted_at is not null then return null; end if;

  update public.dm_messages
     set deleted_at = now(), body = '', media_path = null, media_duration_ms = null
   where id = p_message;

  select id into v_last from public.dm_messages
   where thread_id = v_msg.thread_id order by created_at desc limit 1;
  if v_last = p_message then
    update public.dm_threads set last_body = '🚫 Mensaje eliminado'
     where id = v_msg.thread_id;
  end if;

  return v_msg.media_path;
end;
$$;

revoke all on function public.dm_ensure_thread(uuid) from public, anon;
revoke all on function public.dm_send(uuid, text, text, text, integer, uuid) from public, anon;
revoke all on function public.dm_delete(uuid) from public, anon;
grant execute on function public.dm_ensure_thread(uuid) to authenticated;
grant execute on function public.dm_send(uuid, text, text, text, integer, uuid) to authenticated;
grant execute on function public.dm_delete(uuid) to authenticated;

-- Bucket privado para fotos y audios: {thread_id}/{sender_id}/archivo
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('dm-media', 'dm-media', false, 15728640,
        array['image/jpeg','image/png','image/webp','audio/mp4','audio/m4a','audio/aac','audio/mpeg'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.dm_is_thread_member(p_thread text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.dm_threads t
     where t.id::text = p_thread
       and (select auth.uid()) in (t.user_a, t.user_b)
  );
$$;
revoke all on function public.dm_is_thread_member(text) from public, anon;
grant execute on function public.dm_is_thread_member(text) to authenticated;

drop policy if exists dm_media_member_read on storage.objects;
drop policy if exists dm_media_sender_insert on storage.objects;
drop policy if exists dm_media_sender_delete on storage.objects;

create policy dm_media_member_read on storage.objects
  for select to authenticated
  using (bucket_id = 'dm-media'
         and public.dm_is_thread_member((storage.foldername(name))[1]));

create policy dm_media_sender_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'dm-media'
              and (storage.foldername(name))[2] = (select auth.uid())::text
              and public.dm_is_thread_member((storage.foldername(name))[1]));

create policy dm_media_sender_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'dm-media'
         and (storage.foldername(name))[2] = (select auth.uid())::text);
