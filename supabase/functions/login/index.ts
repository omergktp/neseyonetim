// supabase/functions/login/index.ts
//
// Özel giriş korunuyor: firma_kodu + telefon + sifre doğrulanır; ardından
// personel GoTrue'da bir gölge kullanıcıya eşlenir ve GERÇEK bir Supabase
// oturumu (ES256 imzalı access token + refresh token) döndürülür. Proje
// asimetrik imzalama anahtarları kullandığı için özel HS256 üretimi geçersiz;
// bu köprü sayesinde PostgREST/Realtime/Storage token'ı doğrudan tanır.
//
// Özel claim'ler (firma_id / personel_id / rol) kullanıcının app_metadata'sına
// yazılır ve her girişte tazelenir; RLS bunları app.current_* ile okur.
//
// Gerekli secret yok — SUPABASE_URL, SUPABASE_ANON_KEY ve
// SUPABASE_SERVICE_ROLE_KEY otomatik sağlanır.

import { createClient } from "jsr:@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs@2.4.3";
import { corsHeaders } from "../_shared/cors.ts";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Personelin GoTrue gölge kullanıcısının e-postası (gerçek posta gitmez).
function bridgeEmail(personelId: number | string): string {
  return `p${personelId}@personel.glowsaha.app`;
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

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  // Service role ile bağlan (RLS'i atlar; giriş öncesi kimlik yok).
  const admin = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

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
    .select("id, ad_soyad, sifre, rol, aktif, auth_user_id")
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

  // 4) GoTrue gölge kullanıcısını hazırla; claim'leri her girişte tazele.
  const email = bridgeEmail(personel.id);
  const appMeta = {
    firma_id: String(firma.id),
    personel_id: String(personel.id),
    rol: personel.rol,
  };

  let authUserId: string | null = personel.auth_user_id;
  if (!authUserId) {
    const { data: created, error: cErr } = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      app_metadata: appMeta,
    });
    if (cErr) {
      // Kullanıcı zaten var olabilir (örn. auth_user_id kaydı kaybolduysa):
      // magiclink üretimi kullanıcıyı e-postayla bulur, id'yi oradan alırız.
      const { data: linkData, error: lErr } = await admin.auth.admin.generateLink({
        type: "magiclink",
        email,
      });
      if (lErr || !linkData?.user) return json({ message: "Oturum açılamadı." }, 500);
      authUserId = linkData.user.id;
    } else {
      authUserId = created.user.id;
    }
    await admin.from("personeller").update({ auth_user_id: authUserId }).eq("id", personel.id);
  }

  const { error: uErr } = await admin.auth.admin.updateUserById(authUserId!, {
    app_metadata: appMeta,
  });
  if (uErr) return json({ message: "Oturum açılamadı." }, 500);

  // 5) Oturum üret: magiclink token'ı sunucu tarafında doğrulanır ve
  //    GoTrue gerçek bir oturum (access + refresh token) döndürür.
  const { data: link, error: gErr } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  if (gErr || !link?.properties?.hashed_token) {
    return json({ message: "Oturum açılamadı." }, 500);
  }

  const verifyRes = await fetch(`${supabaseUrl}/auth/v1/verify`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: anonKey },
    body: JSON.stringify({ type: "magiclink", token_hash: link.properties.hashed_token }),
  });
  if (!verifyRes.ok) return json({ message: "Oturum açılamadı." }, 500);
  const session = await verifyRes.json();

  // Eski login.php cevabıyla uyumlu + Supabase oturumu
  return json({
    message: "Giriş başarılı.",
    access_token: session.access_token,
    refresh_token: session.refresh_token ?? null,
    token_type: "bearer",
    expires_in: session.expires_in,
    kullanici: { ad_soyad: personel.ad_soyad, rol: personel.rol },
    firma: { ad: firma.ad, logo: firma.logo, tema_rengi: firma.hex_color },
  });
});
