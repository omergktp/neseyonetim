# Supabase Geçişi — Kurulum ve Uygulama Kılavuzu

Proje: **Neşe Yönetim** (glow_saha) — PHP+MySQL → **Supabase (Postgres + RLS + Edge Functions + Realtime + Storage)**

Yaklaşım: **Tam Supabase-native.** PHP backend kalkar; Flutter uygulaması doğrudan Supabase'e bağlanır. Giriş korunuyor (firma kodu + telefon + şifre) — bir Edge Function doğrulayıp Supabase-uyumlu JWT üretir, RLS `firma_id` claim'iyle izolasyonu zorlar.

Proje referansı: `bfkiifbzxwhbviluyzcp`

---

## Klasör yapısı

```
supabase/
  config.toml                     # supabase init çıktısı (+ functions.login/notify verify_jwt=false)
  migrations/
    0001_schema.sql               # Postgres şeması (9 tablo, enum, indeks, JWT yardımcıları)
    0002_rls.sql                  # RLS okuma politikaları (çok-kiracılı izolasyon)
    0003_rpc_mobil.sql            # Mobil yazma RPC'leri (report/start/save/update/expense/fcm)
    0004_storage.sql              # Storage bucket'ları + firma-izolasyonlu RLS
    0005_notify_fcm.sql           # FCM/audit/QR altyapısı + app.config + app.notify_personel
    0006_admin_rpc.sql            # Yönetici CRUD RPC'leri + FCM tetikleri + audit
    0007_views_reports.sql        # Okuma görünümleri (security_invoker) + dashboard/rapor
    0008_periodic.sql             # Periyodik üretim + pg_cron (her gece, İstanbul TZ)
  functions/
    _shared/cors.ts
    login/index.ts                # Özel giriş -> Supabase JWT
    notify/index.ts               # DB -> FCM HTTP v1 push
```

---

## Ön koşullar

- Node.js (npx ile Supabase CLI: `npx supabase ...`)
- Supabase hesabı ve bu projeye erişim

---

## 1) CLI'yi projeye bağla (link)

Interaktif giriş gerektiği için bu adımı **kendin** çalıştır (Claude Code'da `! ` önekiyle de çalıştırabilirsin):

```bash
# Kişisel access token ile giriş (tarayıcı açılır)
npx supabase login

# Projeye bağla
npx supabase link --project-ref bfkiifbzxwhbviluyzcp
```

`link` sırasında **veritabanı şifresini** ister (Dashboard > Project Settings > Database > Password).

---

## 2) Şemayı ve politikaları uygula (migration push)

```bash
npx supabase db push
```

Bu, `migrations/` altındaki tüm `.sql` dosyalarını sırayla barındırılan Postgres'e uygular.

> Alternatif (CLI istemiyorsan): her migration dosyasının içeriğini Dashboard > **SQL Editor**'e yapıştırıp çalıştır. Sırayla: 0001 → 0002 → 0003.

---

## 3) Edge Function secret'larını ayarla

```bash
# Login: projenin JWT Secret'ı ile imzalar (Dashboard > Settings > API > JWT Secret)
npx supabase secrets set PROJECT_JWT_SECRET="<JWT_SECRET_DEGERI>"

# Notify (FCM): DB ile paylaşılan gizli anahtar + Firebase servis hesabı JSON'u
npx supabase secrets set NOTIFY_SECRET="<uzun-rastgele-deger>"
npx supabase secrets set FCM_SERVICE_ACCOUNT="$(cat fcm-service-account.json)"
```

`SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY` otomatik sağlanır.

Ardından DB'ye notify hedefini yaz (SQL Editor):

```sql
insert into app.config (key, value) values
  ('notify_url',    'https://bfkiifbzxwhbviluyzcp.supabase.co/functions/v1/notify'),
  ('notify_secret', '<NOTIFY_SECRET ile AYNI deger>')
on conflict (key) do update set value = excluded.value;
```

---

## 4) Edge Function'ları yayınla (deploy)

```bash
npx supabase functions deploy login
npx supabase functions deploy notify
```

## 4b) Flutter: anon anahtarı gir

`mobile/lib/services/supabase_config.dart` içindeki `supabaseAnonKey` alanına
Dashboard > Settings > API > **anon public** anahtarını yapıştır.

Test:

```bash
curl -i -X POST "https://bfkiifbzxwhbviluyzcp.supabase.co/functions/v1/login" \
  -H "Content-Type: application/json" \
  -H "apikey: <ANON_KEY>" \
  -d '{"firma_kodu":"TEST1234","telefon":"05554443322","sifre":"123456"}'
```

Beklenen: `200` ve `access_token` içeren JSON.

---

## 5) Veri göçü (Faz 7)

`supabase/seed_data.sql` — mevcut MySQL verisinin (`firmalar`, `personeller`,
`siteler`, `periyodik_sablonlar`, `is_emirleri`) Postgres INSERT'leri. Şema
(0001..0008) uygulandıktan SONRA çalıştırılır. Düz metin şifreler bcrypt'e
yükseltildi; identity sequence'ler setval ile ilerletildi.

SQL Editor'e yapıştırıp çalıştır **veya**:

```bash
npx supabase db execute --file supabase/seed_data.sql   # (linked proje)
```

---

## Uygulama tarafı (Flutter — Faz 6)

- `supabase_flutter` bağımlılığı eklenir.
- `Supabase.initialize(url, anonKey, accessToken: () async => kayitliToken)` ile
  özel JWT PostgREST/Realtime/Storage'a taşınır (GoTrue kullanılmaz).
- `ApiService` HTTP çağrıları Supabase client çağrılarına dönüşür.
- Görev/arıza listelerinde Realtime abonelikleri.

---

## Neden bu tasarım?

- **Giriş değişmiyor:** Kullanıcılar aynı firma kodu + telefon + şifre ile girer.
- **Güvenlik:** Her tablo RLS ile korunur; token'daki `firma_id` dışına çıkılamaz.
  Anon/erişim anahtarı sızsa bile başka firmanın verisi görülemez.
- **Gerçek zamanlı:** Supabase Realtime ile görev/arıza güncellemeleri anında panele düşer.
- **Sunucu yok:** PHP hosting/XAMPP gerekmez; her yerden erişim.
