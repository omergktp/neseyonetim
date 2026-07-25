// supabase/functions/notify/index.ts
//
// DB (pg_net, app.notify_personel) -> bu fonksiyon -> FCM HTTP v1.
// Servis hesabıyla OAuth2 access token üretir ve tek cihaza push gönderir.
// Yetkilendirme: pg_net'in gönderdiği "x-notify-secret" başlığı NOTIFY_SECRET
// ile eşleşmeli (bu fonksiyon verify_jwt=false ile herkese açık uçtur).
//
// Gerekli secret'lar:
//   NOTIFY_SECRET         -> app.config.notify_secret ile AYNI değer
//   FCM_SERVICE_ACCOUNT   -> Firebase servis hesabı JSON'unun TAMAMI (string)
//   (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY otomatik sağlanır)

import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

interface NotifyBody {
  personel_id: number;
  baslik: string;
  govde: string;
  data?: Record<string, unknown>;
}

async function getAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error("OAuth2 token alınamadı: " + JSON.stringify(json));
  return json.access_token as string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method", { status: 405 });

  // Paylaşılan gizli anahtar doğrulaması
  const secret = Deno.env.get("NOTIFY_SECRET");
  if (!secret || req.headers.get("x-notify-secret") !== secret) {
    return new Response("unauthorized", { status: 401 });
  }

  let body: NotifyBody;
  try {
    body = await req.json();
  } catch {
    return new Response("bad request", { status: 400 });
  }
  if (!body.personel_id) return new Response(JSON.stringify({ skipped: "no personel_id" }), { status: 200 });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // Personelin cihaz token'ı
  const { data: personel } = await admin
    .from("personeller")
    .select("fcm_token")
    .eq("id", body.personel_id)
    .maybeSingle();

  const deviceToken = personel?.fcm_token;
  if (!deviceToken) return new Response(JSON.stringify({ skipped: "no fcm_token" }), { status: 200 });

  // Servis hesabı + OAuth2
  const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!saRaw) return new Response(JSON.stringify({ error: "FCM_SERVICE_ACCOUNT yok" }), { status: 500 });
  const sa = JSON.parse(saRaw) as { client_email: string; private_key: string; project_id: string };

  let accessToken: string;
  try {
    accessToken = await getAccessToken(sa);
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 502 });
  }

  // FCM v1 data payload: tüm değerler string olmalı
  const dataStr: Record<string, string> = {};
  for (const [k, v] of Object.entries(body.data ?? {})) dataStr[k] = String(v);

  const fcmRes = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: deviceToken,
          notification: { title: body.baslik, body: body.govde },
          data: dataStr,
          android: { priority: "high" },
        },
      }),
    },
  );

  // Geçersiz/kayıtsız token -> temizle (bir sonraki girişte yeniden yazılır)
  if (fcmRes.status === 404) {
    await admin.from("personeller").update({ fcm_token: null }).eq("id", body.personel_id);
    return new Response(JSON.stringify({ cleared: true }), { status: 200 });
  }

  const fcmJson = fcmRes.ok ? { ok: true } : { ok: false, detail: await fcmRes.text() };
  return new Response(JSON.stringify(fcmJson), { status: fcmRes.ok ? 200 : 502 });
});
