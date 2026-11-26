-- Aviso push de una promoción de Pedalea Plus a los teléfonos de quienes
-- NO son Plus (los suscriptores no lo reciben).
--
-- Cuándo usarlo: solo cuando el precio nuevo YA se vea en la pantalla de
-- Plus de la app (lo entrega Google Play). Si se envía antes, el aviso dice
-- un precio y la app muestra otro.
--
-- Cómo: Supabase → SQL Editor → pegar → Run. Al tocar el aviso se abre la
-- pantalla de Plus (desde la versión 1.4.2; en versiones anteriores abre la app).

select net.http_post(
  url := 'https://ocheyavlacprkvbongno.supabase.co/functions/v1/send-push',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'x-push-secret', (
      select decrypted_secret from vault.decrypted_secrets
      where name = 'push_webhook_secret' limit 1
    )
  ),
  body := jsonb_build_object(
    'table', 'plus_promo',
    'op', 'INSERT',
    'record', jsonb_build_object(
      'title', 'Pedalea Plus ahora a $1.990 🚴',                                          -- máx. 60 caracteres
      'body',  'Rutas, Momentos y bicis sin límite, mapa de calor y más. Menos que un café al mes.'  -- máx. 180
    )
  ),
  timeout_milliseconds := 15000
) as request_id;

-- Para ver el resultado (cuántos se enviaron), unos segundos después:
-- select status_code, content from net._http_response order by id desc limit 1;
