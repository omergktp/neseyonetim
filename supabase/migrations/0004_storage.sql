-- =====================================================================
-- 0004_storage.sql  —  Supabase Storage bucket'ları + RLS
--
-- PHP tarafında dosyalar backend/uploads/ altına yazılıyordu. Native
-- geçişte tüm dosyalar Storage'a taşınır. Kiracı izolasyonu DOSYA YOLU
-- ile sağlanır: her nesnenin yolu "{firma_id}/..." ile başlar; RLS ilk
-- klasör segmentini JWT'deki firma_id ile karşılaştırır.
--
-- Bucket'lar:
--   is-emri-fotograf : iş emri kapanış fotoğrafları        (özel)
--   ariza-fotograf   : arıza + çözüm fotoğrafları           (özel)
--   masraf-fis       : fiş/fatura görselleri                (özel)
--   firma-logo       : firma logoları (giriş ekranı markası) (genel)
-- =====================================================================

insert into storage.buckets (id, name, public)
values
    ('is-emri-fotograf', 'is-emri-fotograf', false),
    ('ariza-fotograf',   'ariza-fotograf',   false),
    ('masraf-fis',       'masraf-fis',       false),
    ('firma-logo',       'firma-logo',       true)
on conflict (id) do nothing;

-- Yardımcı: nesne yolunun ilk klasörü (firma_id) JWT ile eşleşiyor mu?
-- (storage.foldername(name))[1] -> ilk segment.
-- Politikalarda doğrudan kullanıyoruz.

-- ---------------------------------------------------------------------
-- ÖZEL bucket'lar: is-emri-fotograf, ariza-fotograf, masraf-fis
--   SELECT + INSERT: aynı firmadaki giriş yapmış kullanıcı
--   UPDATE + DELETE: yalnız yönetici (aynı firma)
-- ---------------------------------------------------------------------
create policy "ozel_select" on storage.objects
    for select to authenticated
    using (
        bucket_id in ('is-emri-fotograf', 'ariza-fotograf', 'masraf-fis')
        and (storage.foldername(name))[1] = app.current_firma_id()::text
    );

create policy "ozel_insert" on storage.objects
    for insert to authenticated
    with check (
        bucket_id in ('is-emri-fotograf', 'ariza-fotograf', 'masraf-fis')
        and (storage.foldername(name))[1] = app.current_firma_id()::text
    );

create policy "ozel_update" on storage.objects
    for update to authenticated
    using (
        bucket_id in ('is-emri-fotograf', 'ariza-fotograf', 'masraf-fis')
        and (storage.foldername(name))[1] = app.current_firma_id()::text
        and app.is_yonetici()
    );

create policy "ozel_delete" on storage.objects
    for delete to authenticated
    using (
        bucket_id in ('is-emri-fotograf', 'ariza-fotograf', 'masraf-fis')
        and (storage.foldername(name))[1] = app.current_firma_id()::text
        and app.is_yonetici()
    );

-- ---------------------------------------------------------------------
-- GENEL bucket: firma-logo
--   SELECT: herkes (public) — giriş ekranında logo gösterimi için
--   INSERT/UPDATE/DELETE: yalnız yönetici (aynı firma)
-- ---------------------------------------------------------------------
create policy "logo_select_public" on storage.objects
    for select to anon, authenticated
    using (bucket_id = 'firma-logo');

create policy "logo_insert" on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'firma-logo'
        and (storage.foldername(name))[1] = app.current_firma_id()::text
        and app.is_yonetici()
    );

create policy "logo_update" on storage.objects
    for update to authenticated
    using (
        bucket_id = 'firma-logo'
        and (storage.foldername(name))[1] = app.current_firma_id()::text
        and app.is_yonetici()
    );

create policy "logo_delete" on storage.objects
    for delete to authenticated
    using (
        bucket_id = 'firma-logo'
        and (storage.foldername(name))[1] = app.current_firma_id()::text
        and app.is_yonetici()
    );
