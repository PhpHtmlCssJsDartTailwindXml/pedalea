-- Notificaciones push (FCM): llegan aunque la app esté cerrada.
--
-- Flujo: INSERT/UPDATE en una tabla social → trigger → pg_net llama a la
-- Edge Function `send-push` → la función decide a quién avisar y envía el
-- push por FCM a los teléfonos registrados en `device_tokens`.
--
-- Requisitos fuera de esta migración:
--   1. Secreto en Vault llamado 'push_webhook_secret' (valor aleatorio). La
--      Edge Function lo lee con push_webhook_secret() para validar que la
--      llamada viene de estos triggers.
--   2. Edge Function `send-push` desplegada, con el secreto
--      FCM_SERVICE_ACCOUNT_JSON (cuenta de servicio de Firebase).
-- Sin ellos los triggers no hacen nada visible: nunca bloquean ni hacen
-- fallar el INSERT original.

create extension if not exists pg_net;

-- ── Tokens de dispositivo ──────────────────────────────────────────────
create table if not exists public.device_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  platform   text not null default 'android',
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Cada quien solo ve sus propios tokens. Se escriben únicamente mediante
-- las funciones de abajo (no hay políticas de INSERT/UPDATE/DELETE).
drop policy if exists device_tokens_select_own on public.device_tokens;
create policy device_tokens_select_own on public.device_tokens
  for select using (auth.uid() = user_id);

-- Registra (o reasigna) el token de este teléfono a la cuenta con sesión.
-- Un mismo teléfono puede cambiar de cuenta: el token pasa a la nueva.
create or replace function public.register_device_token(
  p_token text,
  p_platform text default 'android'
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if p_token is null or length(p_token) < 20 or length(p_token) > 4096 then
    raise exception 'invalid_token';
  end if;
  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), coalesce(p_platform, 'android'), now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

-- Al cerrar sesión: el teléfono deja de recibir avisos. Se llama ya sin
-- sesión, por eso también la puede ejecutar `anon`; solo borra el token
-- exacto que se le pasa, que únicamente conoce ese teléfono.
create or replace function public.unregister_device_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.device_tokens where token = p_token;
$$;

revoke all on function public.register_device_token(text, text) from public;
revoke all on function public.unregister_device_token(text) from public;
grant execute on function public.register_device_token(text, text) to authenticated;
grant execute on function public.unregister_device_token(text) to anon, authenticated;

-- ── Trigger genérico: avisa a la Edge Function ─────────────────────────
create or replace function public.notify_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
begin
  -- Solo cambios que generan aviso (evita llamadas inútiles).
  if tg_table_name = 'follows' then
    if tg_op = 'INSERT' and new.status is distinct from 'pending' then
      return new;
    end if;
    if tg_op = 'UPDATE' and not (
      new.status = 'accepted' and old.status is distinct from 'accepted'
    ) then
      return new;
    end if;
  end if;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'push_webhook_secret'
  limit 1;
  if v_secret is null then
    return new; -- push aún sin configurar
  end if;

  perform net.http_post(
    url := 'https://ocheyavlacprkvbongno.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'table', tg_table_name,
      'op', tg_op,
      'record', to_jsonb(new)
    ),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  -- Un fallo del aviso jamás debe impedir guardar el mensaje / like / etc.
  return new;
end;
$$;

revoke all on function public.notify_push() from public;

drop trigger if exists push_follows_ins on public.follows;
create trigger push_follows_ins
  after insert on public.follows
  for each row execute function public.notify_push();

drop trigger if exists push_follows_upd on public.follows;
create trigger push_follows_upd
  after update of status on public.follows
  for each row execute function public.notify_push();

drop trigger if exists push_post_likes_ins on public.post_likes;
create trigger push_post_likes_ins
  after insert on public.post_likes
  for each row execute function public.notify_push();

drop trigger if exists push_post_comments_ins on public.post_comments;
create trigger push_post_comments_ins
  after insert on public.post_comments
  for each row execute function public.notify_push();

drop trigger if exists push_dm_messages_ins on public.dm_messages;
create trigger push_dm_messages_ins
  after insert on public.dm_messages
  for each row execute function public.notify_push();

drop trigger if exists push_event_messages_ins on public.event_messages;
create trigger push_event_messages_ins
  after insert on public.event_messages
  for each row execute function public.notify_push();

-- La Edge Function (service_role) lee el secreto para validar las llamadas.
create or replace function public.push_webhook_secret()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select decrypted_secret from vault.decrypted_secrets
  where name = 'push_webhook_secret' limit 1;
$$;

revoke all on function public.push_webhook_secret() from public, anon, authenticated;
grant execute on function public.push_webhook_secret() to service_role;

-- Crea el secreto del webhook con un valor aleatorio (solo si no existe).
-- Nadie necesita verlo: los triggers y la Edge Function lo leen de Vault.
select vault.create_secret(
  replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
  'push_webhook_secret'
)
where not exists (
  select 1 from vault.secrets where name = 'push_webhook_secret'
);
