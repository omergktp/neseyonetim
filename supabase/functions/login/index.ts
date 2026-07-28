// supabase/functions/login/index.ts
//
// Özel giriş: firma_kodu + telefon + sifre doğrulanır; personel GoTrue'da bir
// gölge kullanıcıya eşlenir ve GERÇEK bir Supabase oturumu (access + refresh
// token) döndürülür. Özel claim'ler (firma_id / personel_id / rol) kullanıcının
// app_metadata'sına yazılır ve her girişte tazelenir; RLS bunları app.current_*
// ile okur.
//
// Sertleştirmeler (0011 ile birlikte):
//  * Hız sınırı: (firma_kodu|telefon|ip) başına 5 hatalı deneme -> 15 dk kilit
//    (login_guard RPC; yalnız service_role çağırabilir).
//  * Numaralandırma oracle'ı kapalı: firma yok / kullanıcı yok / şifre yanlış
//    ayrımı yapılmaz — tek tip 401. Kullanıcı bulunamadığında da sahte bcrypt
//    karşılaştırması yapılır (zamanlama farkı sızdırmaz).
//  * Gölge e-posta tahmin edilemez: p-<rastgele-uuid>@personel.blokent.app.
//    Eski öngörülebilir (p<id>@...) adresler ilk girişte rastgeleye taşınır.
//  * createUser hatasında e-postayla kullanıcı devralma (generateLink fallback)
//    KALDIRILDI — "ilk kullanımda güven" açığıydı.
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

const GENEL_HATA = "Firma kodu, telefon veya şifre hatalı.";
// Zamanlama eşitleme için sabit (geçerli biçimli, anlamsız) bcrypt hash'i.
const SAHTE_HASH = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy";

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

  // ---- Hız sınırı anahtarı: firma_kodu|telefon|ip ----
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "bilinmiyor";
  const kilitAnahtari = `${firmaKodu}|${telefon}|${ip}`;

  const guard = async (olay: "kontrol" | "hata" | "basari") => {
    const { data } = await admin.rpc("login_guard", {
      p_anahtar: kilitAnahtari,
      p_olay: olay,
    });
    return data as { kilitli?: boolean; kalan_sn?: number } | null;
  };

  const kilit = await guard("kontrol");
  if (kilit?.kilitli) {
    return json(
      { message: "Çok fazla hatalı deneme. Lütfen 15 dakika sonra tekrar deneyin." },
      429,
    );
  }

  // Tek tip başarısızlık: sayaç artar, ayrıntı sızdırılmaz.
  const basarisiz = async () => {
    const g = await guard("hata");
    if (g?.kilitli) {
      return json(
        { message: "Çok fazla hatalı deneme. Lütfen 15 dakika sonra tekrar deneyin." },
        429,
      );
    }
    return json({ message: GENEL_HATA }, 401);
  };

  // 1) Firma
  const { data: firma, error: fErr } = await admin
    .from("firmalar")
    .select("id, ad, logo, hex_color, aktif")
    .eq("firma_kodu", firmaKodu)
    .maybeSingle();

  if (fErr) return json({ message: "Sunucu hatası." }, 500);
  if (!firma) {
    bcrypt.compareSync(sifre, SAHTE_HASH); // zamanlama eşitleme
    return await basarisiz();
  }

  // 2) Personel (Multi-Tenant: firma_id + telefon)
  const { data: personel, error: pErr } = await admin
    .from("personeller")
    .select("id, ad_soyad, sifre, rol, aktif, auth_user_id")
    .eq("firma_id", firma.id)
    .eq("telefon", telefon)
    .maybeSingle();

  if (pErr) return json({ message: "Sunucu hatası." }, 500);
  if (!personel) {
    bcrypt.compareSync(sifre, SAHTE_HASH); // zamanlama eşitleme
    return await basarisiz();
  }

  // 3) Şifre doğrulama. PHP password_hash bcrypt üretir ($2y$); bcryptjs
  //    $2a$/$2b$ bekler — $2y$ önekini normalize et (algoritma aynı).
  const stored = (personel.sifre ?? "").replace(/^\$2y\$/, "$2a$");
  const gecerli = bcrypt.compareSync(sifre, stored);
  if (!gecerli) return await basarisiz();

  // Hesap durumu ancak doğru şifreden SONRA açıklanır (numaralandırma önlenir).
  if (firma.aktif === false) return json({ message: "Firma hesabı aktif değil." }, 403);
  if (personel.aktif === false) return json({ message: "Kullanıcı hesabı aktif değil." }, 403);

  await guard("basari");

  // 4) GoTrue gölge kullanıcısını hazırla; claim'leri her girişte tazele.
  const appMeta = {
    firma_id: String(firma.id),
    personel_id: String(personel.id),
    rol: personel.rol,
  };

  let authUserId: string | null = personel.auth_user_id;
  let email: string | null = null;

  if (!authUserId) {
    // Yeni köprü kullanıcısı: tahmin edilemez rastgele e-posta.
    email = `p-${crypto.randomUUID()}@personel.blokent.app`;
    const { data: created, error: cErr } = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      app_metadata: appMeta,
    });
    // NOT: hata durumunda e-postayla kullanıcı devralma YOK (güvenlik).
    if (cErr || !created?.user) return json({ message: "Oturum açılamadı." }, 500);
    authUserId = created.user.id;
    const { error: bErr } = await admin
      .from("personeller")
      .update({ auth_user_id: authUserId })
      .eq("id", personel.id);
    if (bErr) return json({ message: "Oturum açılamadı." }, 500);
  } else {
    const { data: mevcut, error: gErr } = await admin.auth.admin.getUserById(authUserId);
    if (gErr || !mevcut?.user) return json({ message: "Oturum açılamadı." }, 500);
    email = mevcut.user.email ?? null;
    // Eski öngörülebilir adresleri (p<id>@...) rastgeleye taşı.
    if (!email || /^p\d+@/.test(email)) {
      email = `p-${crypto.randomUUID()}@personel.blokent.app`;
      const { error: eErr } = await admin.auth.admin.updateUserById(authUserId, {
        email,
        email_confirm: true,
      });
      if (eErr) return json({ message: "Oturum açılamadı." }, 500);
    }
  }

  const { error: uErr } = await admin.auth.admin.updateUserById(authUserId!, {
    app_metadata: appMeta,
  });
  if (uErr) return json({ message: "Oturum açılamadı." }, 500);

  // 5) Oturum üret: magiclink token'ı sunucu tarafında doğrulanır ve
  //    GoTrue gerçek bir oturum (access + refresh token) döndürür.
  const { data: link, error: lErr } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email: email!,
  });
  if (lErr || !link?.properties?.hashed_token) {
    return json({ message: "Oturum açılamadı." }, 500);
  }

  const verifyRes = await fetch(`${supabaseUrl}/auth/v1/verify`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: anonKey },
    body: JSON.stringify({ type: "magiclink", token_hash: link.properties.hashed_token }),
  });
  if (!verifyRes.ok) return json({ message: "Oturum açılamadı." }, 500);
  const session = await verifyRes.json();

  // Logo DB'de "firma-logo/{firma_id}/..." yolu olarak durur (public bucket);
  // istemciler için doğrudan görüntülenebilir URL'e çevrilir.
  const logoUrl = firma.logo
    ? (/^https?:/.test(firma.logo)
      ? firma.logo
      : `${supabaseUrl}/storage/v1/object/public/${firma.logo}`)
    : null;

  // Eski login.php cevabıyla uyumlu + Supabase oturumu
  return json({
    message: "Giriş başarılı.",
    access_token: session.access_token,
    refresh_token: session.refresh_token ?? null,
    token_type: "bearer",
    expires_in: session.expires_in,
    kullanici: { ad_soyad: personel.ad_soyad, rol: personel.rol },
    firma: { ad: firma.ad, logo: firma.logo, logo_url: logoUrl, tema_rengi: firma.hex_color },
  });
});
