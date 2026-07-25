// supabase/functions/login/index.ts
//
// Özel giriş korunuyor: firma_kodu + telefon + sifre doğrulanır ve
// Supabase'in kabul edeceği (proje JWT secret'ı ile HS256 imzalı) bir
// access token üretilir. Token'a firma_id / personel_id / rol claim'leri
// gömülür; Postgres RLS bunları okuyup çok-kiracılı izolasyonu uygular.
//
// Gerekli Edge Function secret'ları:
//   PROJECT_JWT_SECRET  -> Supabase Dashboard > Project Settings > API > JWT Secret
//   (SUPABASE_URL ve SUPABASE_SERVICE_ROLE_KEY otomatik sağlanır)

import { createClient } from "jsr:@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import bcrypt from "npm:bcryptjs@2.4.3";
import { corsHeaders } from "../_shared/cors.ts";

const TOKEN_TTL_SN = 60 * 60 * 24 * 7; // 7 gün (eski davranışla aynı)

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Proje JWT secret'ından HS256 imzalama anahtarı üret.
async function importHmacKey(secret: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ message: "Yalnızca POST." }, 405);

  let body: { firma_kodu?: string; telefon?: string; sifre?: string };
  try {
    body = await req.json();
  } catch {
    return json({ message: "Geçersiz istek gövdesi." }, 400);
  }

  const firmaKodu = (body.firma_kodu ?? "").toString().trim();
  const telefon = (body.telefon ?? "").toString().trim();
  const sifre = (body.sifre ?? "").toString();

  if (!firmaKodu || !telefon || !sifre) {
    return json(
      { message: "Eksik bilgi gönderildi. (firma_kodu, telefon, sifre gerekli)" },
      400,
    );
  }

  const jwtSecret = Deno.env.get("PROJECT_JWT_SECRET");
  if (!jwtSecret) return json({ message: "Sunucu yapılandırma hatası." }, 500);

  // Service role ile bağlan (RLS'i atlar; giriş öncesi kimlik yok).
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // 1) Firma
  const { data: firma, error: fErr } = await admin
    .from("firmalar")
    .select("id, ad, logo, hex_color, aktif")
    .eq("firma_kodu", firmaKodu)
    .maybeSingle();

  if (fErr) return json({ message: "Sunucu hatası." }, 500);
  if (!firma) return json({ message: "Geçersiz firma kodu." }, 404);
  if (firma.aktif === false) return json({ message: "Firma hesabı aktif değil." }, 403);

  // 2) Personel (Multi-Tenant: firma_id + telefon)
  const { data: personel, error: pErr } = await admin
    .from("personeller")
    .select("id, ad_soyad, sifre, rol, aktif")
    .eq("firma_id", firma.id)
    .eq("telefon", telefon)
    .maybeSingle();

  if (pErr) return json({ message: "Sunucu hatası." }, 500);
  if (!personel) return json({ message: "Kullanıcı bulunamadı." }, 404);
  if (personel.aktif === false) return json({ message: "Kullanıcı hesabı aktif değil." }, 403);

  // 3) Şifre doğrulama. PHP password_hash bcrypt üretir ($2y$); bcryptjs
  //    $2a$/$2b$ bekler — $2y$ önekini normalize et (algoritma aynı).
  const stored = (personel.sifre ?? "").replace(/^\$2y\$/, "$2a$");
  const gecerli = bcrypt.compareSync(sifre, stored);
  if (!gecerli) return json({ message: "Şifre hatalı." }, 401);

  // 4) Supabase uyumlu JWT üret.
  const key = await importHmacKey(jwtSecret);
  const now = getNumericDate(0);
  const token = await create(
    { alg: "HS256", typ: "JWT" },
    {
      // Supabase/PostgREST'in beklediği standart claim'ler
      role: "authenticated",
      aud: "authenticated",
      iss: "neseyonetim-login",
      sub: String(personel.id),
      iat: now,
      exp: getNumericDate(TOKEN_TTL_SN),
      // RLS'in okuduğu özel claim'ler (app.current_* fonksiyonları)
      firma_id: String(firma.id),
      personel_id: String(personel.id),
      rol: personel.rol,
    },
    key,
  );

  // Eski login.php cevabıyla uyumlu + Supabase access_token
  return json({
    message: "Giriş başarılı.",
    access_token: token,
    token_type: "bearer",
    expires_in: TOKEN_TTL_SN,
    kullanici: { ad_soyad: personel.ad_soyad, rol: personel.rol },
    firma: { ad: firma.ad, logo: firma.logo, tema_rengi: firma.hex_color },
  });
});
