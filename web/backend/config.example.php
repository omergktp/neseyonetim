<?php
// backend/config.example.php
// Bu dosyayı config.php olarak kopyalayın ve kendi değerlerinizi girin.
// config.php git'e dahil DEĞİLDİR (gizli anahtarlar içerir).

// Veritabanı Ayarları
define('DB_HOST', 'localhost');
define('DB_NAME', 'glow_saha');
define('DB_USER', 'root');
define('DB_PASS', '');
define('DB_CHARSET', 'utf8mb4');

// Uygulama Ayarları
define('APP_URL', 'http://localhost/neseyonetim/backend');
define('JWT_SECRET', 'BURAYA-UZUN-RASTGELE-BIR-ANAHTAR-YAZIN'); // ör: bin2hex(random_bytes(32))

// --- Mobil Uygulama Sürüm Kontrolü (Zorunlu Güncelleme) ---
define('MIN_APP_VERSION', '1.0.0');     // Çalışmaya izin verilen en düşük sürüm
define('LATEST_APP_VERSION', '1.0.0');  // Mağazadaki güncel sürüm
define('APP_STORE_URL', 'https://play.google.com/store/apps/details?id=com.example.glow_saha');

// --- FCM (Firebase Cloud Messaging) - HTTP v1 API ---
define('FCM_PROJECT_ID', 'PROJE-KIMLIGINIZ');
// secrets/ klasörü .htaccess ile web erişimine tamamen kapalıdır — anahtarlar oraya konur.
define('FCM_SERVICE_ACCOUNT', __DIR__ . '/secrets/fcm-service-account.json');

// Zaman Dilimi Ayarı
date_default_timezone_set('Europe/Istanbul');

// Ortam: 'development' veya 'production'. Canlıya alırken 'production' yapın.
define('APP_ENV', 'development');

// Hata Gösterimi: Yalnızca geliştirme ortamında ekrana basılır.
if (APP_ENV === 'production') {
    ini_set('display_errors', 0);
    ini_set('display_startup_errors', 0);
    ini_set('log_errors', 1);
    error_reporting(E_ALL & ~E_DEPRECATED & ~E_NOTICE);
} else {
    ini_set('display_errors', 1);
    ini_set('display_startup_errors', 1);
    error_reporting(E_ALL);
}
