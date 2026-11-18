# Migraciones de la base de datos

Cambios a la base de datos de Pedalea en Supabase (PostgreSQL), en archivos SQL.
Las tablas base (`profiles`, `bike_alerts`, `events` y otras) se crearon antes desde el
panel de Supabase. Esta carpeta guarda los cambios hechos después: funciones nuevas,
reglas de acceso (RLS) y medidas de seguridad.

Todas ya están aplicadas en el proyecto de producción. Se aplican desde
**Supabase → SQL Editor** (pegar el archivo y ejecutar) o con `supabase db push`.
Casi todas se pueden volver a ejecutar sin problema (son idempotentes).

## Orden de aplicación

> **Importante:** el orden real **no es** el orden alfabético de los archivos.
> `20261124_security_stage2.sql` se aplicó antes que `20261116_fix_profile_private.sql`.
> Si se aplican al revés, la etapa 2 vuelve a quitar el permiso de lectura sobre
> `profiles` y la app deja de poder guardar el perfil.

| # | Archivo | Qué hace |
|---|---|---|
| 1 | `20261012_dm_rich_messages.sql` | Mensajes directos con fotos, audios, responder y eliminar para todos. |
| 2 | `20261012_dm_media_body_and_km_security.sql` | Permite mensajes sin texto (foto o audio) y protege los km de cada usuario. |
| 3 | `20261012_fix_profile_protect_triggers.sql` | Arregla los triggers que impiden que un usuario se active Plus o cambie sus km. |
| 4 | `20261013_community_stats.sql` | Totales de la comunidad para la pantalla de inicio (solo agregados, sin datos personales). |
| 5 | `20261111_push_notifications.sql` | Notificaciones push (FCM): triggers que llaman a la Edge Function `send-push`. |
| 6 | `20261112_bikes_and_alert_impact.sql` | «Mis bicis» (km y mantención) y «Tu aporte ayudó a…» (impacto de las alertas). |
| 7 | `20261115_plus_hardening.sql` | Pedalea Plus validado en el servidor (eventos privados, límites y suscripción). |
| 8 | `20261116_notifications_and_open_social.sql` | Momentos abiertos a todos (respetando bloqueos) y centro de notificaciones. |
| 9 | `20261117_security_stage1.sql` | Seguridad, etapa 1: funciones nuevas compatibles con versiones antiguas de la app. |
| 10 | `20261124_security_stage2.sql` | Seguridad, etapa 2: cierra los accesos directos que usaba la app antigua. |
| 11 | `20261116_fix_profile_private.sql` | Contacto de emergencia en una tabla privada; arregla el guardado del perfil. |
| 12 | `20261117_fall_events.sql` | Registro anónimo del detector de caídas (sin usuario ni ubicación). |
| 13 | `20261118_pump_votes.sql` | Votación de la comunidad sobre bombas de aire en bencineras. |
| 14 | `20261125_plus_share_uses.sql` | Imágenes Plus gratis al compartir estadísticas (2 por semana). |

## Seguridad

- Ningún archivo contiene claves ni contraseñas. El secreto de las notificaciones push
  se genera al azar al aplicar la migración 5 y queda guardado en Supabase Vault.
- Las tablas sensibles no se escriben directamente desde la app: pasan por funciones
  del servidor (`security definer`) que validan al usuario.
