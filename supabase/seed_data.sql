-- =====================================================================
-- seed_data.sql — glow_saha (MySQL) verisinin Postgres'e aktarımı
-- Şema (0001..0008) UYGULANDIKTAN SONRA çalıştırılır.
-- Not: fotoğraf yolları eski (uploads/...) biçimdedir; dosyalar Storage'a
-- taşınmadıysa görüntülenmez (imzalı URL üretimi güvenle null döner).
--
-- GÜVENLİK: Tüm personel şifreleri DEMO değeridir: "GlowDemo2026".
-- Gerçek ortama açmadan önce panelden her personel için yeni şifre belirle.
-- (Gerçek hash'ler ve FCM token'ları bu dosyadan kaldırılmıştır; canlı
-- ortamdaki karşılıkları rotasyona sokulmuştur.)
-- =====================================================================

begin;

-- firmalar (1 satır)
insert into firmalar (id, firma_kodu, ad, logo, hex_color, olusturma_tarihi, aktif) values ('1', 'TEST1234', 'Demo Tesis Yönetimi', NULL, '#1E40AF', '2026-05-22 14:40:19', true);
select setval(pg_get_serial_sequence('public.firmalar','id'), coalesce((select max(id) from firmalar), 1), true);

-- personeller (4 satır)
insert into personeller (id, firma_id, ad_soyad, telefon, sifre, rol, fcm_token, olusturma_tarihi, aktif) values ('1', '1', 'Admin Kullanıcı', '05554443322', '$2a$10$cjJjklpba0DywR8fxtDdX.3IpbZILcXYbFa7NAHZEllXVzQ43k1K6', 'yonetici', NULL, '2026-05-22 14:40:19', true);
insert into personeller (id, firma_id, ad_soyad, telefon, sifre, rol, fcm_token, olusturma_tarihi, aktif) values ('2', '1', 'Test Personel', '05555555555', '$2a$10$cjJjklpba0DywR8fxtDdX.3IpbZILcXYbFa7NAHZEllXVzQ43k1K6', 'temizlik', NULL, '2026-06-13 11:01:16', true);
insert into personeller (id, firma_id, ad_soyad, telefon, sifre, rol, fcm_token, olusturma_tarihi, aktif) values ('3', '1', 'Test Teknik', '05444444444', '$2a$10$cjJjklpba0DywR8fxtDdX.3IpbZILcXYbFa7NAHZEllXVzQ43k1K6', 'teknik', NULL, '2026-06-13 12:53:32', true);
insert into personeller (id, firma_id, ad_soyad, telefon, sifre, rol, fcm_token, olusturma_tarihi, aktif) values ('5', '1', 'ahmet yönen (temizlik)', '05553333333', '$2a$10$cjJjklpba0DywR8fxtDdX.3IpbZILcXYbFa7NAHZEllXVzQ43k1K6', 'temizlik', NULL, '2026-06-19 15:49:04', true);
select setval(pg_get_serial_sequence('public.personeller','id'), coalesce((select max(id) from personeller), 1), true);

-- siteler (6 satır)
insert into siteler (id, firma_id, ad, adres, enlem, boylam, qr_kod, olusturma_tarihi, aktif) values ('1', '1', 'Güneş Sitesi Merkez', 'İstanbul', NULL, NULL, 'SAHA-D22F669CB7', '2026-05-22 14:40:19', true);
insert into siteler (id, firma_id, ad, adres, enlem, boylam, qr_kod, olusturma_tarihi, aktif) values ('4', '1', 'Elit Yaşam Evleri', 'Ataşehir, İstanbul', '40.99250000', '29.12750000', 'SAHA-3B5F1D788D', '2026-06-14 00:13:48', true);
insert into siteler (id, firma_id, ad, adres, enlem, boylam, qr_kod, olusturma_tarihi, aktif) values ('5', '1', 'Bahçeşehir Konakları', 'Başakşehir, İstanbul', '41.07000000', '28.65000000', 'SAHA-3D8012566D', '2026-06-14 00:13:48', true);
insert into siteler (id, firma_id, ad, adres, enlem, boylam, qr_kod, olusturma_tarihi, aktif) values ('7', '1', 'NEŞE YÖNETİM', '', '38.76072181', '30.54604737', 'SAHA-8136CA4DBD', '2026-06-19 12:38:38', true);
insert into siteler (id, firma_id, ad, adres, enlem, boylam, qr_kod, olusturma_tarihi, aktif) values ('8', '1', 'Glow Saha Test', '', '38.75513964', '30.54703532', 'SAHA-34E0020090', '2026-06-19 12:41:06', true);
insert into siteler (id, firma_id, ad, adres, enlem, boylam, qr_kod, olusturma_tarihi, aktif) values ('9', '1', 'neşe yönetim erenler', '38.815299760610685, 30.543028918348067', '38.81529100', '30.54332900', 'SAHA-303C2D231F', '2026-06-19 15:40:15', true);
select setval(pg_get_serial_sequence('public.siteler','id'), coalesce((select max(id) from siteler), 1), true);

-- periyodik_sablonlar (1 satır)
insert into periyodik_sablonlar (id, firma_id, site_id, personel_id, baslik, aciklama, alt_gorevler, tekrar_tipi, tekrar_gunu, son_uretim_tarihi, aktif, olusturma_tarihi) values ('5', '1', '9', '5', 'apartman temizliği', '', 'temizlik', 'gunluk', NULL, '2026-06-19', true, '2026-06-19 15:49:36');
select setval(pg_get_serial_sequence('public.periyodik_sablonlar','id'), coalesce((select max(id) from periyodik_sablonlar), 1), true);

-- is_emirleri (1 satır)
insert into is_emirleri (id, firma_id, site_id, personel_id, sablon_id, baslik, aciklama, durum, qr_kod, planlanan_baslangic_tarihi, termin_tarihi, tamamlanma_tarihi, tamamlanma_enlem, tamamlanma_boylam, kapanis_fotograf_url, olusturma_tarihi) values ('31', '1', '4', '2', NULL, 'temizlik', '', 'bekliyor', NULL, '2026-07-01 16:00:00', NULL, NULL, NULL, NULL, NULL, '2026-07-01 16:00:50');
select setval(pg_get_serial_sequence('public.is_emirleri','id'), coalesce((select max(id) from is_emirleri), 1), true);

-- is_emirleri_alt_gorevler: veri yok

-- arizalar: veri yok

-- malzeme_talepleri: veri yok

-- audit_log: veri yok

commit;
