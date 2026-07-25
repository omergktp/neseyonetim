-- =====================================================================
-- 0002_rls.sql  —  Çok-kiracılı (multi-tenant) Row Level Security
--
-- Güvenlik modeli (PHP endpoint yetki matrisinden birebir türetildi):
--   * OKUMA (SELECT): doğrudan PostgREST + aşağıdaki RLS politikaları.
--       - yonetici  -> firmasındaki tüm satırlar
--       - temizlik/teknik -> yalnız kendine ait / atanmış satırlar
--   * YAZMA (INSERT/UPDATE/DELETE): tablo düzeyinde VARSAYILAN RED.
--       Tüm yazmalar 0003_rpc.sql'deki SECURITY DEFINER fonksiyonlarından
--       geçer (durum makinesi, rol ve sahiplik kontrolleri orada; PHP
--       uçlarının aynısı). Böylece kolon/duruma özel kurallar RLS'in
--       ifade edemediği yerde bile güvence altında olur.
--
--   firma_id daima JWT claim'inden gelir (istemci gönderemez). Anon
--   kullanıcıda firma_id claim'i yoktur -> current_firma_id() NULL ->
--   hiçbir satır görünmez.
-- =====================================================================

-- Rollere tablo ayrıcalıkları (RLS bunların ÜSTÜNDE filtreler).
-- service_role RLS'i baypas eder (Edge Function / RPC sahibi).
grant usage on schema app to authenticated, anon, service_role;
grant execute on all functions in schema app to authenticated, anon, service_role;

grant select on
    firmalar, personeller, siteler, is_emirleri, is_emirleri_alt_gorevler,
    arizalar, malzeme_talepleri, periyodik_sablonlar, audit_log
    to authenticated;

grant all on
    firmalar, personeller, siteler, is_emirleri, is_emirleri_alt_gorevler,
    arizalar, malzeme_talepleri, periyodik_sablonlar, audit_log
    to service_role;

-- RLS'i tüm tablolarda aç.
alter table firmalar                  enable row level security;
alter table personeller               enable row level security;
alter table siteler                   enable row level security;
alter table is_emirleri               enable row level security;
alter table is_emirleri_alt_gorevler  enable row level security;
alter table arizalar                  enable row level security;
alter table malzeme_talepleri         enable row level security;
alter table periyodik_sablonlar       enable row level security;
alter table audit_log                 enable row level security;

-- ---------------------------------------------------------------------
-- firmalar: kullanıcı yalnız kendi firmasını okur (marka/logo/renk için).
-- (Giriş anında firma araması service_role ile yapılır, RLS'e takılmaz.)
-- ---------------------------------------------------------------------
create policy firmalar_select on firmalar
    for select to authenticated
    using (id = app.current_firma_id());

-- ---------------------------------------------------------------------
-- personeller: yönetici tüm firmayı; personel yalnız kendini görür.
-- ---------------------------------------------------------------------
create policy personeller_select on personeller
    for select to authenticated
    using (
        firma_id = app.current_firma_id()
        and (app.is_yonetici() or id = app.current_personel_id())
    );

-- ---------------------------------------------------------------------
-- siteler: firmadaki tüm giriş yapmış kullanıcılar okur (seçim listeleri).
-- ---------------------------------------------------------------------
create policy siteler_select on siteler
    for select to authenticated
    using (firma_id = app.current_firma_id());

-- ---------------------------------------------------------------------
-- is_emirleri: yönetici tüm firmayı; personel yalnız kendine atanmışları.
-- ---------------------------------------------------------------------
create policy is_emirleri_select on is_emirleri
    for select to authenticated
    using (
        firma_id = app.current_firma_id()
        and (app.is_yonetici() or personel_id = app.current_personel_id())
    );

-- ---------------------------------------------------------------------
-- is_emirleri_alt_gorevler: bağlı iş emrinin sahipliğine göre.
-- ---------------------------------------------------------------------
create policy alt_gorevler_select on is_emirleri_alt_gorevler
    for select to authenticated
    using (
        firma_id = app.current_firma_id()
        and (
            app.is_yonetici()
            or exists (
                select 1 from is_emirleri ie
                where ie.id = is_emirleri_alt_gorevler.is_emri_id
                  and ie.personel_id = app.current_personel_id()
            )
        )
    );

-- ---------------------------------------------------------------------
-- arizalar: yönetici tümünü; personel kendine atanmış (teknik) veya
-- kendi bildirdiği arızaları görür.
-- ---------------------------------------------------------------------
create policy arizalar_select on arizalar
    for select to authenticated
    using (
        firma_id = app.current_firma_id()
        and (
            app.is_yonetici()
            or teknik_personel_id = app.current_personel_id()
            or bildiren_personel_id = app.current_personel_id()
        )
    );

-- ---------------------------------------------------------------------
-- malzeme_talepleri: yönetici tümünü; personel yalnız kendi taleplerini.
-- ---------------------------------------------------------------------
create policy masraf_select on malzeme_talepleri
    for select to authenticated
    using (
        firma_id = app.current_firma_id()
        and (app.is_yonetici() or personel_id = app.current_personel_id())
    );

-- ---------------------------------------------------------------------
-- periyodik_sablonlar: yalnız yönetici.
-- ---------------------------------------------------------------------
create policy sablon_select on periyodik_sablonlar
    for select to authenticated
    using (firma_id = app.current_firma_id() and app.is_yonetici());

-- ---------------------------------------------------------------------
-- audit_log: yalnız yönetici okur. Yazma yalnız SECURITY DEFINER
-- fonksiyonlarından (log_action) yapılır.
-- ---------------------------------------------------------------------
create policy audit_select on audit_log
    for select to authenticated
    using (firma_id = app.current_firma_id() and app.is_yonetici());

-- NOT: Bilinçli olarak INSERT/UPDATE/DELETE politikası YOK.
-- authenticated rol için yazma varsayılan olarak reddedilir; tüm
-- yazmalar 0003_rpc.sql'deki SECURITY DEFINER fonksiyonlarından geçer.
