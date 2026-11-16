-- Bomba de aire en bencineras: la comunidad vota si hay o no.
--
-- · Cada usuario vota 👍 (hay) o 👎 (no hay) una vez por ronda (puede cambiar
--   su voto mientras la ronda siga abierta).
-- · Al llegar a 5 votos iguales se decide: «hay» o «no hay», y la votación
--   queda cerrada 30 días. Pasado ese plazo se abre una ronda nueva desde 0
--   (el resultado anterior se sigue mostrando hasta que haya uno nuevo).
-- · Todo pasa por las funciones de abajo: la app no escribe las tablas.

create table if not exists public.pump_reports (
  service_id   text primary key check (service_id ~ '^(node|way|relation)/[0-9]{1,15}$'),
  status       text check (status in ('yes', 'no')),
  decided_at   timestamptz,
  locked_until timestamptz,
  round        int not null default 1
);

create table if not exists public.pump_votes (
  service_id text not null,
  round      int  not null,
  user_id    uuid not null references auth.users(id) on delete cascade,
  vote       boolean not null,
  created_at timestamptz not null default now(),
  primary key (service_id, round, user_id)
);

alter table public.pump_reports enable row level security;
alter table public.pump_votes enable row level security;
revoke all on public.pump_reports from anon, authenticated;
revoke all on public.pump_votes from anon, authenticated;

-- Estado de una bencinera (cualquiera puede verlo).
create or replace function public.pump_status(p_service text)
returns json
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  r public.pump_reports;
  v_round int;
  v_yes int := 0;
  v_no int := 0;
  v_mine boolean;
  v_open boolean;
begin
  select * into r from public.pump_reports where service_id = p_service;
  v_open := r.locked_until is null or r.locked_until <= now();
  v_round := coalesce(r.round, 1);
  if v_open then
    select count(*) filter (where vote), count(*) filter (where not vote)
      into v_yes, v_no
      from public.pump_votes where service_id = p_service and round = v_round;
    select vote into v_mine from public.pump_votes
     where service_id = p_service and round = v_round and user_id = auth.uid();
  end if;
  return json_build_object(
    'status', r.status,
    'decided_at', r.decided_at,
    'locked_until', case when v_open then null else r.locked_until end,
    'yes', v_yes,
    'no', v_no,
    'my_vote', v_mine,
    'needed', 5
  );
end;
$$;

-- Votar. p_vote: true = hay bomba, false = no hay, null = quitar mi voto.
create or replace function public.vote_pump(p_service text, p_vote boolean)
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  me uuid := auth.uid();
  r public.pump_reports;
  v_yes int;
  v_no int;
begin
  if me is null then
    raise exception 'not_authenticated';
  end if;
  if p_service !~ '^(node|way|relation)/[0-9]{1,15}$' then
    raise exception 'invalid_service';
  end if;

  insert into public.pump_reports (service_id) values (p_service)
  on conflict (service_id) do nothing;
  select * into r from public.pump_reports where service_id = p_service for update;

  if r.locked_until is not null and r.locked_until > now() then
    raise exception 'locked';
  end if;

  if p_vote is null then
    delete from public.pump_votes
     where service_id = p_service and round = r.round and user_id = me;
  else
    insert into public.pump_votes (service_id, round, user_id, vote)
    values (p_service, r.round, me, p_vote)
    on conflict (service_id, round, user_id)
    do update set vote = excluded.vote, created_at = now();
  end if;

  select count(*) filter (where vote), count(*) filter (where not vote)
    into v_yes, v_no
    from public.pump_votes where service_id = p_service and round = r.round;

  if v_yes >= 5 or v_no >= 5 then
    update public.pump_reports
       set status = case when v_yes >= 5 then 'yes' else 'no' end,
           decided_at = now(),
           locked_until = now() + interval '30 days',
           round = r.round + 1
     where service_id = p_service;
  end if;

  return public.pump_status(p_service);
end;
$$;

revoke all on function public.pump_status(text) from public;
revoke all on function public.vote_pump(text, boolean) from public, anon;
grant execute on function public.pump_status(text) to anon, authenticated;
grant execute on function public.vote_pump(text, boolean) to authenticated;
