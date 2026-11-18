-- 1) Momentos: cualquier ciclista puede dar me gusta y comentar (antes solo con
--    follow mutuo). Se mantiene el respeto a los bloqueos en ambos sentidos.
-- 2) Centro de notificaciones: cada aviso que envía send-push queda guardado
--    para verlo desde el menú aunque el push se haya perdido o descartado.

-- ── Bloqueos (helper con security definer: blocked_users solo es legible por
--    quien bloquea, así que la política no podría ver el bloqueo del autor) ──
create or replace function public.not_blocked(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select not exists (
    select 1 from public.blocked_users x
    where (x.blocker_id = a and x.blocked_id = b)
       or (x.blocker_id = b and x.blocked_id = a)
  );
$$;
revoke all on function public.not_blocked(uuid, uuid) from public, anon;
grant execute on function public.not_blocked(uuid, uuid) to authenticated;

-- ── Me gusta ──────────────────────────────────────────────────────────────
drop policy if exists post_likes_insert_mutual on public.post_likes;
drop policy if exists post_likes_insert_open on public.post_likes;
create policy post_likes_insert_open on public.post_likes
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and post_author_id = (select p.user_id from public.posts p where p.id = post_likes.post_id)
    and public.not_blocked((select auth.uid()), post_author_id)
  );

-- ── Comentarios ──────────────────────────────────────────────────────────
drop policy if exists post_comments_insert_mutual on public.post_comments;
drop policy if exists post_comments_insert_open on public.post_comments;
create policy post_comments_insert_open on public.post_comments
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and post_author_id = (select p.user_id from public.posts p where p.id = post_comments.post_id)
    and public.not_blocked((select auth.uid()), post_author_id)
  );

-- ── Centro de notificaciones ─────────────────────────────────────────────
create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  type        text not null,
  title       text not null,
  body        text not null default '',
  payload     text not null default '',
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

-- Solo el dueño las ve, las marca como leídas o las borra. Las inserta
-- únicamente la Edge Function send-push (service_role, sin política).
drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own on public.notifications
  for delete to authenticated using (user_id = (select auth.uid()));

-- Marca como leídas todas (p_ids null) o algunas notificaciones del usuario.
create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns void
language sql
security definer
set search_path to 'public'
as $$
  update public.notifications
     set read_at = now()
   where user_id = auth.uid()
     and read_at is null
     and (p_ids is null or id = any(p_ids));
$$;
revoke all on function public.mark_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;
