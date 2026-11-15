// Edge Function `send-push`: convierte un cambio de la base de datos en una
// notificación push (FCM) para los teléfonos del destinatario.
//
// La llaman los triggers `notify_push()` de la BD (ver
// supabase/migrations/20261111_push_notifications.sql), nunca la app.
//
// Secreto necesario:
//   FCM_SERVICE_ACCOUNT_JSON  — JSON completo de la cuenta de servicio de
//                               Firebase (Configuración → Cuentas de servicio
//                               → Generar nueva clave privada).
// Desplegar con verify_jwt = false: cada llamada trae el secreto de Vault
// 'push_webhook_secret', que solo conocen los triggers y esta función (lo
// lee con la RPC push_webhook_secret(), permitida solo a service_role).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

type Row = Record<string, unknown>;

interface Push {
  to: string[]; // user ids
  type: string; // chat | dm | follow_req | follow_accept | like | comment | reply | alert_impact
  title: string;
  body: string;
  payload: string; // lo que la app usa para abrir la pantalla correcta
  channel: "group_chat_messages" | "social_activity" | "app_news";
  data?: Record<string, string>;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const str = (v: unknown) => (typeof v === "string" ? v : "");
const clip = (s: string, n = 140) => (s.length > n ? s.slice(0, n - 1) + "…" : s);

async function nameOf(userId: string): Promise<string> {
  const { data } = await supabase
    .from("profiles")
    .select("username, full_name")
    .eq("id", userId)
    .maybeSingle();
  const u = str(data?.username).trim();
  const f = str(data?.full_name).trim();
  return u || f || "Alguien";
}

/** Decide a quién avisar y con qué texto. null = este cambio no avisa. */
async function buildPush(table: string, op: string, r: Row): Promise<Push | null> {
  switch (table) {
    case "follows": {
      const follower = str(r.follower_id);
      const following = str(r.following_id);
      if (op === "INSERT" && r.status === "pending") {
        return {
          to: [following],
          type: "follow_req",
          title: "Nueva solicitud de seguimiento",
          body: `${await nameOf(follower)} quiere seguirte`,
          payload: "follow_req",
          channel: "social_activity",
        };
      }
      if (op === "UPDATE" && r.status === "accepted") {
        return {
          to: [follower],
          type: "follow_accept",
          title: "Te aceptaron",
          body: `${await nameOf(following)} aceptó tu solicitud de seguimiento`,
          payload: `follow_accept|${following}`,
          channel: "social_activity",
        };
      }
      return null;
    }

    case "post_likes": {
      const who = str(r.user_id);
      const author = str(r.post_author_id);
      if (!author || who === author) return null;
      return {
        to: [author],
        type: "like",
        title: `A ${await nameOf(who)} le gustó tu momento`,
        body: "Toca para ver tu perfil",
        payload: `post_activity|${author}`,
        channel: "social_activity",
      };
    }

    case "post_comments": {
      const who = str(r.user_id);
      const text = clip(str(r.body).trim());
      const name = await nameOf(who);
      if (r.parent_id) {
        // Respuesta a un comentario: se avisa a quien se le respondió.
        const target = str(r.reply_to_user_id);
        if (!target || target === who) return null;
        return {
          to: [target],
          type: "reply",
          title: `${name} respondió tu comentario`,
          body: text || "Toca para ver",
          payload: `post_activity|${target}`,
          channel: "social_activity",
        };
      }
      const author = str(r.post_author_id);
      if (!author || author === who) return null;
      return {
        to: [author],
        type: "comment",
        title: "Nuevo comentario en tu momento",
        body: text ? `${name}: ${text}` : `${name} comentó tu momento`,
        payload: `post_activity|${author}`,
        channel: "social_activity",
      };
    }

    case "dm_messages": {
      const sender = str(r.sender_id);
      const recipient = str(r.recipient_id);
      if (!recipient || sender === recipient || r.deleted_at) return null;
      const name = await nameOf(sender);
      const text = clip(str(r.body).trim());
      const kind = str(r.kind) || "text";
      const body = kind === "image"
        ? (text ? `📷 ${text}` : "📷 Foto")
        : kind === "audio"
        ? "🎤 Mensaje de voz"
        : (text || "Te envió un mensaje");
      return {
        to: [recipient],
        type: "dm",
        title: name,
        body,
        payload: `dm|${sender}|${name}`,
        channel: "social_activity",
        data: { sender_id: sender },
      };
    }

    case "app_update": {
      // Aviso a todos los teléfonos registrados: hay versión nueva en Play.
      // Se envía a mano con supabase/snippets/aviso_nueva_version.sql.
      const { data: rows } = await supabase.from("device_tokens").select("user_id");
      const users = [...new Set((rows ?? []).map((t) => t.user_id as string))];
      if (users.length === 0) return null;
      return {
        to: users,
        type: "app_update",
        title: clip(str(r.title).trim(), 60) || "Nueva versión de Pedalea 🚲",
        body: clip(str(r.body).trim(), 180) ||
          "Hay mejoras nuevas. Toca para actualizar.",
        payload: "app_update",
        channel: "app_news",
      };
    }

    case "alert_milestone": {
      // Lo envía register_alert_view() al llegar a 3, 10, 25… ciclistas.
      const author = str(r.author_id);
      const count = Number(r.count) || 0;
      if (!author || count <= 0) return null;
      const labels: Record<string, string> = {
        danger: "peligro",
        theft: "robo",
        construction: "obras",
        accident: "accidente",
      };
      const what = labels[str(r.type)] ?? "incidente";
      const place = clip(str(r.place).trim(), 60);
      return {
        to: [author],
        type: "alert_impact",
        title: `Tu alerta ya ayudó a ${count} ciclistas 🙌`,
        body: place
          ? `Tu reporte de ${what} en ${place} lo vieron ${count} ciclistas. ¡Gracias por cuidar a la comunidad!`
          : `Tu reporte de ${what} lo vieron ${count} ciclistas. ¡Gracias por cuidar a la comunidad!`,
        payload: "my_impact",
        channel: "social_activity",
      };
    }

    case "event_messages": {
      const sender = str(r.user_id);
      const eventId = str(r.event_id);
      if (!eventId) return null;
      const { data: ev } = await supabase
        .from("events")
        .select("title, user_id, participants_ids")
        .eq("id", eventId)
        .maybeSingle();
      if (!ev) return null;
      const members = new Set<string>(
        Array.isArray(ev.participants_ids)
          ? ev.participants_ids.filter((x: unknown) => typeof x === "string")
          : [],
      );
      if (ev.user_id) members.add(ev.user_id as string); // quien creó el grupo
      members.delete(sender);
      if (members.size === 0) return null;
      const title = str(ev.title).trim() || "Grupo";
      const name = await nameOf(sender);
      const text = clip(str(r.message).trim()) || "Envió un mensaje";
      return {
        to: [...members],
        type: "chat",
        title,
        body: `${name}: ${text}`,
        payload: `chat|${eventId}|${title}`,
        channel: "group_chat_messages",
        data: { event_id: eventId, sender_name: name, text },
      };
    }
  }
  return null;
}

// ── FCM HTTP v1 ─────────────────────────────────────────────────────────
interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

let cachedToken: { value: string; exp: number } | null = null;

const b64url = (data: ArrayBuffer | string) => {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : new Uint8Array(data);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

/** Token OAuth de Google para llamar a FCM, firmado con la cuenta de servicio. */
async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.value;

  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key
    .replace(/-----[A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(sig)}`,
    }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`oauth ${res.status}: ${JSON.stringify(body)}`);
  cachedToken = { value: body.access_token, exp: now + (body.expires_in ?? 3600) };
  return cachedToken.value;
}

let webhookSecret: string | null = null;

async function expectedSecret(): Promise<string | null> {
  if (webhookSecret) return webhookSecret;
  const { data, error } = await supabase.rpc("push_webhook_secret");
  if (error || typeof data !== "string" || data.length < 20) return null;
  webhookSecret = data;
  return webhookSecret;
}

Deno.serve(async (req) => {
  const secret = await expectedSecret();
  if (!secret || req.headers.get("x-push-secret") !== secret) {
    return json({ error: "unauthorized" }, 401);
  }

  let input: { table?: string; op?: string; record?: Row };
  try {
    input = await req.json();
  } catch {
    return json({ error: "bad_json" }, 400);
  }
  if (!input.table || !input.record) return json({ error: "bad_request" }, 400);

  try {
    const push = await buildPush(input.table, input.op ?? "INSERT", input.record);
    if (!push || push.to.length === 0) return json({ sent: 0 });

    // Centro de notificaciones: se guarda una copia para verla en la app
    // aunque el push no llegue o se descarte. Los mensajes de chat y directos
    // tienen su propio contador de no leídos, por eso no se guardan aquí.
    if (push.type !== "chat" && push.type !== "dm") {
      const { error: insErr } = await supabase.from("notifications").insert(
        push.to.map((uid) => ({
          user_id: uid,
          type: push.type,
          title: push.title,
          body: push.body,
          payload: push.payload,
        })),
      );
      if (insErr) console.error("notifications insert:", insErr.message);
    }

    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
    if (!saRaw) return json({ skipped: "fcm_not_configured" });

    const { data: rows } = await supabase
      .from("device_tokens")
      .select("token")
      .in("user_id", push.to);
    const tokens = (rows ?? []).map((t) => t.token as string);
    if (tokens.length === 0) return json({ sent: 0, reason: "no_tokens" });

    const sa = JSON.parse(saRaw) as ServiceAccount;
    const bearer = await accessToken(sa);
    const url =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    const dead: string[] = [];
    let sent = 0;
    await Promise.all(tokens.map(async (token) => {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${bearer}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: push.title, body: push.body },
            data: {
              type: push.type,
              title: push.title,
              body: push.body,
              payload: push.payload,
              ...(push.data ?? {}),
            },
            android: {
              priority: "HIGH",
              notification: {
                channel_id: push.channel,
                // Avisos del mismo chat/tipo se reemplazan en vez de apilarse.
                tag: push.type === "chat" || push.type === "dm"
                  ? push.payload.split("|").slice(0, 2).join("|")
                  : push.type,
              },
            },
          },
        }),
      });
      if (res.ok) {
        sent++;
        return;
      }
      const err = await res.text();
      // Token de una app desinstalada o caducado: se limpia.
      if (res.status === 404 || err.includes("UNREGISTERED")) dead.push(token);
      else console.error(`fcm ${res.status}: ${err}`);
    }));

    if (dead.length > 0) {
      await supabase.from("device_tokens").delete().in("token", dead);
    }
    return json({ sent, removed: dead.length });
  } catch (e) {
    console.error("send-push:", e);
    return json({ error: String(e) }, 500);
  }
});
