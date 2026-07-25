<?php
// backend/core/upload.php
// Base64 görsel verisini sunucuda dosya olarak kaydeder ve erişilebilir göreli yolu döndürür.
// Mobil uygulama fotoğrafı (filigranlı) base64 olarak gönderir; DB'de sadece bu yol saklanır.

function save_base64_image($base64, $subdir) {
    if (!is_string($base64) || $base64 === '') {
        return null;
    }

    // "data:image/jpeg;base64,...." öneki varsa ayıkla
    if (($pos = strpos($base64, 'base64,')) !== false) {
        $base64 = substr($base64, $pos + 7);
    }

    $data = base64_decode($base64, true);
    if ($data === false) {
        return null;
    }

    // Boyut sınırı: 10 MB (çözülmüş veri). Depolamayı dolduracak yüklemeleri engeller.
    if (strlen($data) > 10 * 1024 * 1024) {
        return null;
    }

    // İçerik gerçekten görsel mi? (uzantı .jpg'e zorlanıyor olsa da rastgele
    // veri barındırmayı engellemek için imza doğrulaması şart.)
    $info = @getimagesizefromstring($data);
    if ($info === false || !in_array($info[2], [IMAGETYPE_JPEG, IMAGETYPE_PNG, IMAGETYPE_WEBP], true)) {
        return null;
    }

    // backend/uploads/<subdir>/ klasörünü oluştur
    $dir = __DIR__ . '/../uploads/' . $subdir;
    if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
        return null;
    }

    $filename = $subdir . '_' . uniqid('', true) . '.jpg';
    $fullPath = $dir . '/' . $filename;

    if (file_put_contents($fullPath, $data) === false) {
        return null;
    }

    // DB'ye yazılacak göreli yol (backend köküne göre). Panelden ../backend/<yol> ile erişilir.
    return 'uploads/' . $subdir . '/' . $filename;
}
