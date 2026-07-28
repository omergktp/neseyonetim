-- =====================================================================
-- 0012 — Marka yönetimi yalnız SÜPER ADMİN'e taşınır
--
-- İş modeli ayrımı: platform sahibi (süper admin) firmaları, markayı
-- (ad / tema rengi / logo) ve hesapları yönetir; firma yöneticileri
-- yalnız iş akışını (personel, tesis, iş emri, arıza, masraf) yönetir.
--
-- Bu migration firma yöneticisinin marka değiştirme yollarını sunucu
-- tarafında kapatır (arayüzden kaldırmak yetmez; API'den çağrılabilirdi):
--   1) admin_firma_guncelle RPC'si authenticated'dan geri alınır
--      (yalnız service_role — süper admin edge fonksiyonu — kullanır).
--   2) firma-logo bucket'ının yazma politikaları kaldırılır
--      (public SELECT kalır: giriş ekranı logoyu göstermeye devam eder;
--       yazma yalnız service_role ile süper admin fonksiyonundan yapılır).
-- =====================================================================

-- 1) Firma ayarları RPC'si artık firma yöneticisine kapalı
revoke execute on function
    public.admin_firma_guncelle(text, text, text, boolean)
    from authenticated;

-- 2) firma-logo bucket yazma politikaları kaldırılır (okuma public kalır)
drop policy if exists "logo_insert" on storage.objects;
drop policy if exists "logo_update" on storage.objects;
drop policy if exists "logo_delete" on storage.objects;
