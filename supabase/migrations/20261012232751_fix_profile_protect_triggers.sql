-- Arregla los triggers que protegen is_plus y total_km en profiles.
-- Aplicar en Supabase → SQL Editor (proyecto ocheyavlacprkvbongno). Es idempotente.
--
-- Problema: protect_is_plus y protect_total_km eran SECURITY DEFINER (dueño
-- postgres). Dentro de una función así current_user es 'postgres', por lo que
-- is_trusted_writer() siempre devolvía true y la protección nunca se aplicaba:
-- cualquier usuario podía activarse Plus o fijarse los km con un update a su
-- propio perfil.
--
-- Solución: que corran como quien hace el update (SECURITY INVOKER).
--  · Update desde la app (rol authenticated)          → se revierte el cambio.
--  · Edge Function con service_role                   → permitido.
--  · Funciones SECURITY DEFINER del servidor (p. ej.
--    increment_total_km), que corren como postgres     → permitido.

alter function public.protect_is_plus() security invoker;
alter function public.protect_total_km() security invoker;

-- Como invoker, el rol authenticated necesita poder evaluar is_trusted_writer()
-- (solo informa qué rol hace el cambio; no modifica nada).
grant execute on function public.is_trusted_writer() to authenticated;
