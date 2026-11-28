-- Corrige los triggers que protegen alertas, eventos y suscripciones.
--
-- Problema: estos triggers eran SECURITY DEFINER y llaman a
-- is_trusted_writer(), que mira current_user. Dentro de una función
-- SECURITY DEFINER, current_user es el dueño de la función (postgres), así
-- que is_trusted_writer() siempre daba verdadero y los triggers dejaban pasar
-- todo. Por ejemplo, un usuario podía insertar con la API una suscripción
-- activa (Plus gratis en el servidor) o cambiar los votos de su alerta.
--
-- Arreglo: que se ejecuten con los permisos de quien hace el cambio
-- (SECURITY INVOKER). Así current_user es el rol real (authenticated) y la
-- protección funciona. Las funciones del servidor que sí deben poder escribir
-- (vote_alert, join_event, grant_owner_test_plus…) son SECURITY DEFINER: al
-- llamar a estos triggers, current_user es postgres y siguen funcionando.
--
-- Ninguno de estos triggers necesita permisos extra: solo leen el perfil
-- (username, full_name: legibles para authenticated) y plus_active(), que ya
-- es SECURITY DEFINER.

alter function public.bike_alerts_before_insert() security invoker;
alter function public.bike_alerts_protect() security invoker;
alter function public.events_before_insert() security invoker;
alter function public.events_before_update() security invoker;
alter function public.guard_subscription_activation() security invoker;
