-- Registro ANÓNIMO del detector de caídas (sin usuario ni ubicación).
-- Sirve para ajustar los umbrales con casos reales: cuántas alertas fueron
-- caídas y cuántas el ciclista marcó como «Estoy bien».
-- La app solo puede insertar; nadie puede leer desde la app (se revisa en el
-- panel de Supabase). Si esta tabla no existe, la app sigue funcionando igual.

create table if not exists public.fall_events (
  id                 bigint generated always as identity primary key,
  created_at         timestamptz not null default now(),
  trigger            text not null check (trigger in ('impact', 'hardImpact', 'suddenStop')),
  confirmed          boolean not null,
  reason             text not null check (char_length(reason) <= 40),
  strict             boolean not null default false,
  outcome            text not null check (outcome in
                       ('descartada', 'estoy_bien', 'llamo', 'llamada_automatica', 'desactivo')),
  peak_accel         real check (peak_accel between 0 and 200),
  peak_gyro          real check (peak_gyro between 0 and 100),
  speed_before       real check (speed_before between 0 and 200),
  speed_after        real check (speed_after between 0 and 200),
  orientation_change real check (orientation_change between 0 and 180),
  stillness          real check (stillness between 0 and 200)
);

alter table public.fall_events enable row level security;
revoke all on public.fall_events from anon, authenticated;
grant insert (trigger, confirmed, reason, strict, outcome, peak_accel, peak_gyro,
              speed_before, speed_after, orientation_change, stillness)
  on public.fall_events to authenticated;

drop policy if exists fall_events_insert on public.fall_events;
create policy fall_events_insert on public.fall_events
  for insert to authenticated
  with check (true);

-- Consulta útil para ajustar (ejecutar en el panel):
-- select reason, outcome, count(*), avg(peak_accel), avg(orientation_change)
--   from fall_events group by 1, 2 order by 3 desc;
