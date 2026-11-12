-- Aviso push "Nueva versión de Pedalea" a TODOS los teléfonos registrados.
--
-- Cuándo usarlo: solo cuando la versión nueva YA aparezca como
-- "Actualizar" en Play Store en tu propio teléfono. Si se envía antes, la
-- gente abre la app y Play todavía no le ofrece la actualización.
--
-- Cómo: Supabase → SQL Editor → pegar → Run. El texto es general, así
-- que sirve igual para cualquier versión; cámbialo solo si quieres.
-- Al tocar el aviso se abre la app y aparece la pantalla de actualización.

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
    'table', 'app_update',
    'op', 'INSERT',
    'record', jsonb_build_object(
      'title', 'Nueva versión de Pedalea 🚲',               -- máx. 60 caracteres
      'body',  'Ya está disponible una nueva versión de Pedalea con mejoras y novedades. Toca para actualizar. ¡Gracias por pedalear con nosotros!'  -- máx. 180
    )
  ),
  timeout_milliseconds := 15000
) as request_id;

-- Para ver el resultado (cuántos se enviaron), unos segundos después:
-- select status_code, content from net._http_response order by id desc limit 1;
