-- Veritabanı Oluşturma
CREATE DATABASE IF NOT EXISTS glow_saha CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE glow_saha;

-- 1. FİRMALAR TABLOSU
CREATE TABLE IF NOT EXISTS firmalar (
    id INT AUTO_INCREMENT PRIMARY KEY,
    firma_kodu VARCHAR(50) NOT NULL UNIQUE,
    ad VARCHAR(255) NOT NULL,
    logo VARCHAR(255) DEFAULT NULL,
    hex_color VARCHAR(10) DEFAULT '#000000',
    olusturma_tarihi TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    aktif TINYINT(1) DEFAULT 1
);

-- 2. PERSONELLER TABLOSU
-- KURAL 1: Multi-Tenant gereği firma_id içeriyor.
CREATE TABLE IF NOT EXISTS personeller (
    id INT AUTO_INCREMENT PRIMARY KEY,
    firma_id INT NOT NULL,
    ad_soyad VARCHAR(255) NOT NULL,
    telefon VARCHAR(20) NOT NULL,
    sifre VARCHAR(255) NOT NULL,
    rol ENUM('yonetici', 'temizlik', 'teknik') NOT NULL,
    fcm_token VARCHAR(255) DEFAULT NULL,
    olusturma_tarihi TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    aktif TINYINT(1) DEFAULT 1,
    FOREIGN KEY (firma_id) REFERENCES firmalar(id) ON DELETE CASCADE,
    UNIQUE KEY (firma_id, telefon) -- Bir firmada aynı telefon no bir kere olabilir
);

-- 3. SİTELER / TESİSLER TABLOSU
-- KURAL 1: Multi-Tenant gereği firma_id içeriyor.
CREATE TABLE IF NOT EXISTS siteler (
    id INT AUTO_INCREMENT PRIMARY KEY,
    firma_id INT NOT NULL,
    ad VARCHAR(255) NOT NULL,
    adres TEXT,
    enlem DECIMAL(10, 8),
    boylam DECIMAL(11, 8),
    -- Tesise fiziksel olarak asılan benzersiz QR değeri. Personel bu QR'ı okutarak
    -- o tesisteki görevi başlatabilir (konum 50m kuralıyla birlikte doğrulama).
    qr_kod VARCHAR(100) DEFAULT NULL UNIQUE,
    olusturma_tarihi TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    aktif TINYINT(1) DEFAULT 1,
    FOREIGN KEY (firma_id) REFERENCES firmalar(id) ON DELETE CASCADE
);

-- 4. İŞ EMİRLERİ TABLOSU
-- KURAL 1: Multi-Tenant gereği firma_id içeriyor.
CREATE TABLE IF NOT EXISTS is_emirleri (
    id INT AUTO_INCREMENT PRIMARY KEY,
    firma_id INT NOT NULL,
    site_id INT NOT NULL,
    personel_id INT NOT NULL,
    -- Periyodik şablondan üretildiyse kaynağı (cron/"Üret"). Şablon silinince SET NULL olur.
    sablon_id INT DEFAULT NULL,
    baslik VARCHAR(255) NOT NULL,
    aciklama TEXT,
    durum ENUM('bekliyor', 'devam_ediyor', 'tamamlandi', 'iptal') DEFAULT 'bekliyor',
    qr_kod VARCHAR(100) DEFAULT NULL,
    planlanan_baslangic_tarihi DATETIME DEFAULT NULL,
    tamamlanma_tarihi DATETIME DEFAULT NULL,
    tamamlanma_enlem DECIMAL(10, 8) DEFAULT NULL,
    tamamlanma_boylam DECIMAL(11, 8) DEFAULT NULL,
    kapanis_fotograf_url VARCHAR(255) DEFAULT NULL,
    olusturma_tarihi TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (firma_id) REFERENCES firmalar(id) ON DELETE CASCADE,
    FOREIGN KEY (site_id) REFERENCES siteler(id) ON DELETE CASCADE,
    FOREIGN KEY (personel_id) REFERENCES personeller(id) ON DELETE CASCADE
    -- sablon_id FK'si dosyanın sonunda eklenir (periyodik_sablonlar bu tablodan sonra tanımlanıyor).
);

-- 5. İŞ EMİRLERİ ALT GÖREVLER (CHECKLIST) TABLOSU
-- KURAL 1: Multi-Tenant gereği firma_id içeriyor.
CREATE TABLE IF NOT EXISTS is_emirleri_alt_gorevler (
    id INT AUTO_INCREMENT PRIMARY KEY,
    firma_id INT NOT NULL,
    is_emri_id INT NOT NULL,
    gorev_metni VARCHAR(255) NOT NULL,
    yapildi_mi TINYINT(1) DEFAULT 0,
    FOREIGN KEY (firma_id) REFERENCES firmalar(id) ON DELETE CASCADE,
    FOREIGN KEY (is_emri_id) REFERENCES is_emirleri(id) ON DELETE CASCADE
);

-- 6. ARIZALAR TABLOSU
-- KURAL 1: Multi-Tenant gereği firma_id içeriyor.
CREATE TABLE IF NOT EXISTS arizalar (
    id INT AUTO_INCREMENT PRIMARY KEY,
    firma_id INT NOT NULL,
    site_id INT NOT NULL,
    bildiren_personel_id INT NOT NULL,
    teknik_personel_id INT DEFAULT NULL,
    baslik VARCHAR(255) NOT NULL,
    aciklama TEXT,
    teknik_notu TEXT DEFAULT NULL,
    fotograf_url VARCHAR(255) DEFAULT NULL,
    cozum_fotograf_url VARCHAR(255) DEFAULT NULL,
    durum ENUM('acik', 'bekliyor', 'cozuldu', 'iptal', 'dis_destek') DEFAULT 'acik',
    olusturma_tarihi TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    cozum_tarihi DATETIME DEFAULT NULL,
    FOREIGN KEY (firma_id) REFERENCES firmalar(id) ON DELETE CASCADE,
    FOREIGN KEY (site_id) REFERENCES siteler(id) ON DELETE CASCADE,
    FOREIGN KEY (bildiren_personel_id) REFERENCES personeller(id) ON DELETE CASCADE,
    FOREIGN KEY (teknik_personel_id) REFERENCES personeller(id) ON DELETE SET NULL
);

-- 7. MALZEME / MASRAF TALEPLERİ TABLOSU
-- KURAL 1: Multi-Tenant gereği firma_id içeriyor.
CREATE TABLE IF NOT EXISTS malzeme_talepleri (
    id INT AUTO_INCREMENT PRIMARY KEY,
    firma_id INT NOT NULL,
    personel_id INT NOT NULL,
    ariza_id INT DEFAULT NULL,
    is_emri_id INT DEFAULT NULL,
    kalem_adi VARCHAR(255) NOT NULL,
    tutar DECIMAL(10, 2) NOT NULL,
    fis_fatura_fotograf VARCHAR(255) NOT NULL,
    durum ENUM('bekliyor', 'onaylandi', 'reddedildi') DEFAULT 'bekliyor',
    olusturma_tarihi TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (firma_id) REFERENCES firmalar(id) ON DELETE CASCADE,
    FOREIGN KEY (personel_id) REFERENCES personeller(id) ON DELETE CASCADE,
    FOREIGN KEY (ariza_id) REFERENCES arizalar(id) ON DELETE CASCADE,
    FOREIGN KEY (is_emri_id) REFERENCES is_emirleri(id) ON DELETE CASCADE
);

-- 8. PERİYODİK GÖREV ŞABLONLARI TABLOSU
-- KURAL 1: Multi-Tenant gereği firma_id içeriyor.
-- Cron job (backend/cron/periodic_tasks.php) her gece bu şablonlara bakıp
-- tekrar kuralı bugüne denk gelen aktif şablonlardan otomatik iş emri üretir.
CREATE TABLE IF NOT EXISTS periyodik_sablonlar (
    id INT AUTO_INCREMENT PRIMARY KEY,
    firma_id INT NOT NULL,
    site_id INT NOT NULL,
    personel_id INT NOT NULL,
    baslik VARCHAR(255) NOT NULL,
    aciklama TEXT,
    -- Checklist maddeleri (her satır bir alt görev). İş emri üretilirken
    -- is_emirleri_alt_gorevler tablosuna kopyalanır.
    alt_gorevler TEXT DEFAULT NULL,
    tekrar_tipi ENUM('gunluk', 'haftalik', 'aylik') NOT NULL DEFAULT 'gunluk',
    -- haftalik: 1=Pazartesi ... 7=Pazar | aylik: ayın günü 1-31 | gunluk: NULL
    tekrar_gunu TINYINT DEFAULT NULL,
    -- Aynı gün mükerrer üretimi engeller (cron birden çok kez çalışsa bile).
    son_uretim_tarihi DATE DEFAULT NULL,
    aktif TINYINT(1) DEFAULT 1,
    olusturma_tarihi TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (firma_id) REFERENCES firmalar(id) ON DELETE CASCADE,
    FOREIGN KEY (site_id) REFERENCES siteler(id) ON DELETE CASCADE,
    FOREIGN KEY (personel_id) REFERENCES personeller(id) ON DELETE CASCADE
);

-- is_emirleri.sablon_id -> periyodik_sablonlar bağı (her iki tablo da oluştuktan sonra).
-- Şablon silinince üretilmiş iş emirleri SET NULL olur (FK kopmaz; bekleyenler API tarafında ayrıca silinir).
ALTER TABLE is_emirleri
    ADD CONSTRAINT fk_ie_sablon FOREIGN KEY (sablon_id) REFERENCES periyodik_sablonlar(id) ON DELETE SET NULL;
