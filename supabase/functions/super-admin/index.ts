// supabase/functions/super-admin/index.ts
//
// SÜPER ADMİN ucu: platform sahibinin (firmaların değil!) firma açma /
// listeleme / aktif-pasif yönetimi. web/panel/super.html bu ucu çağırır.
//
// Kimlik doğrulama: "x-super-key" başlığı, Supabase secret'ı SUPER_ADMIN_KEY
// ile sabit-zamanlı karşılaştırılır. Anahtar repo'da TUTULMAZ; kurulum:
//   supabase secrets set SUPER_ADMIN_KEY="uzun-rastgele-anahtar"
//
// Kaba kuvvet koruması: yanlış anahtar denemeleri login_guard RPC'sinden
// geçer (IP başına 5 hata -> 15 dk kilit; giriş ekranıyla aynı mekanizma).
//
// İşlemler (POST JSON):
//   { islem: "listele" }
//   { islem: "kur", firma_kodu, ad, hex_color, yonetici_ad, telefon, sifre,
//     logo_base64?, logo_tip? }            — logo süper admin tarafından yüklenir
//   { islem: "logo", firma_id, logo_base64, logo_tip }   — logo yükle/değiştir
//   { islem: "logo", firma_id, kaldir: true }            — logoyu kaldır
//   { islem: "durum", firma_id, aktif }

import { createClient } from "jsr:@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs@2.4.3";
import { corsHeaders } from "../_shared/cors.ts";

// x-super-key başlığına izin ver (paylaşılan listeye ek).
const cors = {
  ...corsHeaders,
  "Access-Control-Allow-Headers":
    corsHeaders["Access-Control-Allow-Headers"] + ", x-super-key",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

// Sabit-zamanlı karşılaştırma: iki değerin SHA-256 özetleri kıyaslanır
// (uzunluk farkı ve erken çıkış zamanlama sızıntısı olmaz).
async function anahtarDogru(verilen: string, beklenen: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(verilen)),
    crypto.subtle.digest("SHA-256", enc.encode(beklenen)),
  ]);
  const av = new Uint8Array(a), bv = new Uint8Array(b);
  let fark = 0;
  for (let i = 0; i < av.length; i++) fark |= av[i] ^ bv[i];
  return fark === 0;
}

// İzin verilen logo türleri -> dosya uzantısı.
const MIME_UZANTI: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
  "image/svg+xml": "svg",
};

// Logoyu firma-logo bucket'ına yükler; DB'de saklanacak "firma-logo/{id}/..."
// yolunu döndürür (login fonksiyonu bu yolu public URL'e çevirir).
// deno-lint-ignore no-explicit-any
async function logoYukle(admin: any, firmaId: number, base64: string, tip: string): Promise<string> {
  const uzanti = MIME_UZANTI[tip];
  if (!uzanti) throw new Error("Logo PNG, JPEG, WebP veya SVG olmalı.");
  const temiz = base64.replace(/^data:[^;]+;base64,/, "");
  let bytes: Uint8Array;
  try {
    bytes = Uint8Array.from(atob(temiz), (c) => c.charCodeAt(0));
  } catch {
    throw new Error("Logo verisi çözümlenemedi.");
  }
  if (bytes.length === 0) throw new Error("Logo dosyası boş.");
  if (bytes.length > 2 * 1024 * 1024) throw new Error("Logo en fazla 2 MB olabilir.");
  const yol = `${firmaId}/logo_${Date.now()}.${uzanti}`;
  const { error } = await admin.storage.from("firma-logo")
    .upload(yol, bytes, { contentType: tip, upsert: true });
  if (error) throw new Error("Logo Storage'a yüklenemedi.");
  return `firma-logo/${yol}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ message: "Yalnızca POST." }, 405);

  const beklenenAnahtar = Deno.env.get("SUPER_ADMIN_KEY") ?? "";
  if (!beklenenAnahtar) {
    return json({ message: "SUPER_ADMIN_KEY tanımlı değil (supabase secrets set)." }, 500);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // ---- Kaba kuvvet koruması (login ile aynı login_guard mekanizması) ----
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "bilinmiyor";
  const kilitAnahtari = `super||${ip}`;
  const guard = async (olay: "kontrol" | "hata" | "basari") => {
    const { data } = await admin.rpc("login_guard", { p_anahtar: kilitAnahtari, p_olay: olay });
    return data as { kilitli?: boolean } | null;
  };

  const kilit = await guard("kontrol");
  if (kilit?.kilitli) {
    return json({ message: "Çok fazla hatalı deneme. 15 dakika sonra tekrar deneyin." }, 429);
  }

  const verilenAnahtar = req.headers.get("x-super-key") ?? "";
  if (!(await anahtarDogru(verilenAnahtar, beklenenAnahtar))) {
    await guard("hata");
    return json({ message: "Yetkisiz." }, 401);
  }
  await guard("basari");

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ message: "Geçersiz istek gövdesi." }, 400);
  }

  const islem = (body.islem ?? "").toString();

  // ---------------- LİSTELE ----------------
  if (islem === "listele") {
    const [{ data: firmalar, error: fErr }, { data: personeller }, { data: siteler }] =
      await Promise.all([
        admin.from("firmalar")
          .select("id, firma_kodu, ad, logo, hex_color, aktif, olusturma_tarihi")
          .order("olusturma_tarihi", { ascending: false }),
        admin.from("personeller").select("firma_id"),
        admin.from("siteler").select("firma_id"),
      ]);
    if (fErr) return json({ message: "Firmalar okunamadı." }, 500);

    const say = (liste: { firma_id: number }[] | null, id: number) =>
      (liste ?? []).filter((x) => String(x.firma_id) === String(id)).length;

    return json({
      firmalar: (firmalar ?? []).map((f) => ({
        ...f,
        personel_sayisi: say(personeller as never, f.id),
        site_sayisi: say(siteler as never, f.id),
      })),
    });
  }

  // ---------------- KUR (yeni firma + ilk yönetici) ----------------
  if (islem === "kur") {
    const firmaKodu = (body.firma_kodu ?? "").toString().trim().toUpperCase();
    const ad = (body.ad ?? "").toString().trim();
    const renk = (body.hex_color ?? "#3B82F6").toString().trim();
    const yoneticiAd = (body.yonetici_ad ?? "").toString().trim();
    const telefon = (body.telefon ?? "").toString().replace(/\D/g, "");
    const sifre = (body.sifre ?? "").toString();

    // Girdi doğrulama — firma_kur.php ile aynı kurallar; şifre politikası 0011 (min 10).
    if (!/^[A-Z0-9]{4,20}$/.test(firmaKodu)) {
      return json({ message: "Firma kodu 4-20 karakter, yalnızca BÜYÜK harf ve rakam olmalı. (örn: NESE2026)" }, 422);
    }
    if (!ad) return json({ message: "Firma adı boş olamaz." }, 422);
    if (!/^#[0-9A-Fa-f]{6}$/.test(renk)) {
      return json({ message: "Tema rengi #RRGGBB biçiminde olmalı. (örn: #3B82F6)" }, 422);
    }
    if (!yoneticiAd) return json({ message: "Yönetici adı boş olamaz." }, 422);
    if (telefon.length < 10) return json({ message: "Telefon numarası geçersiz görünüyor." }, 422);
    if (sifre.length < 10) return json({ message: "Şifre en az 10 karakter olmalı." }, 422);

    // Firma kodu benzersiz mi?
    const { data: mevcut } = await admin
      .from("firmalar").select("id").eq("firma_kodu", firmaKodu).maybeSingle();
    if (mevcut) return json({ message: `'${firmaKodu}' firma kodu zaten kayıtlı.` }, 409);

    // 1) Firma
    const { data: firma, error: fErr } = await admin
      .from("firmalar")
      .insert({ firma_kodu: firmaKodu, ad, hex_color: renk, aktif: true })
      .select("id")
      .single();
    if (fErr || !firma) return json({ message: "Firma oluşturulamadı." }, 500);

    // 2) İlk yönetici (gölge auth kullanıcısı İLK girişte otomatik açılır).
    const { error: pErr } = await admin.from("personeller").insert({
      firma_id: firma.id,
      ad_soyad: yoneticiAd,
      telefon,
      sifre: bcrypt.hashSync(sifre, 10),
      rol: "yonetici",
      aktif: true,
    });
    if (pErr) {
      // Telafi: yönetici açılamadıysa firmayı yarım bırakma.
      await admin.from("firmalar").delete().eq("id", firma.id);
      return json({ message: "Yönetici hesabı oluşturulamadı, kurulum geri alındı." }, 500);
    }

    // 3) Logo (opsiyonel; süper admin yükler — firma sahibi girişte hazır bulur).
    //    Logo hatası kurulumu bozmaz: firma açılır, uyarıyla dönülür.
    let logoUyari: string | null = null;
    const logoBase64 = (body.logo_base64 ?? "").toString();
    if (logoBase64) {
      try {
        const yol = await logoYukle(admin, firma.id, logoBase64, (body.logo_tip ?? "").toString());
        await admin.from("firmalar").update({ logo: yol }).eq("id", firma.id);
      } catch (e) {
        logoUyari = `Firma kuruldu ama logo yüklenemedi: ${(e as Error).message}`;
      }
    }

    return json({
      message: "Firma kuruldu.",
      logo_uyari: logoUyari,
      firma: { id: firma.id, firma_kodu: firmaKodu, ad, hex_color: renk },
    });
  }

  // ---------------- LOGO (yükle / değiştir / kaldır) ----------------
  if (islem === "logo") {
    const firmaId = Number(body.firma_id);
    if (!Number.isInteger(firmaId) || firmaId <= 0) {
      return json({ message: "Geçersiz firma_id." }, 422);
    }
    if (body.kaldir === true) {
      const { error } = await admin.from("firmalar").update({ logo: null }).eq("id", firmaId);
      if (error) return json({ message: "Logo kaldırılamadı." }, 500);
      return json({ message: "Logo kaldırıldı." });
    }
    try {
      const yol = await logoYukle(
        admin, firmaId,
        (body.logo_base64 ?? "").toString(),
        (body.logo_tip ?? "").toString(),
      );
      const { error } = await admin.from("firmalar").update({ logo: yol }).eq("id", firmaId);
      if (error) return json({ message: "Logo kaydedilemedi." }, 500);
      return json({ message: "Logo yüklendi.", logo: yol });
    } catch (e) {
      return json({ message: (e as Error).message }, 422);
    }
  }

  // ---------------- DURUM (aktif / pasif) ----------------
  if (islem === "durum") {
    const firmaId = Number(body.firma_id);
    const aktif = body.aktif === true;
    if (!Number.isInteger(firmaId) || firmaId <= 0) {
      return json({ message: "Geçersiz firma_id." }, 422);
    }
    const { error } = await admin.from("firmalar").update({ aktif }).eq("id", firmaId);
    if (error) return json({ message: "Durum güncellenemedi." }, 500);
    return json({ message: aktif ? "Firma aktifleştirildi." : "Firma pasifleştirildi." });
  }

  return json({ message: "Bilinmeyen işlem." }, 400);
});
