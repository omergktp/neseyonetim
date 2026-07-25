<?php
// backend/api/version.php
// Mobil uygulama açılışında (splash) çağrılır. Kimlik doğrulama GEREKMEZ.
// İstemci kendi sürümünü ?v=1.0.0 ile gönderir; sunucu güncelleme zorunlu mu bildirir.

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, X-Requested-With");

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require_once __DIR__ . '/../config.php';

$istemciSurum = isset($_GET['v']) ? trim($_GET['v']) : null;

// İstemci sürümü MIN_APP_VERSION'dan eski mi? (version_compare "1.0.0" < "1.1.0" => true)
$guncellemeZorunlu = false;
if ($istemciSurum !== null && $istemciSurum !== '') {
    $guncellemeZorunlu = version_compare($istemciSurum, MIN_APP_VERSION, '<');
}

http_response_code(200);
echo json_encode([
    "min_version"        => MIN_APP_VERSION,
    "latest_version"     => LATEST_APP_VERSION,
    "store_url"          => APP_STORE_URL,
    "guncelleme_zorunlu" => $guncellemeZorunlu,
    "mesaj"              => $guncellemeZorunlu
        ? "Uygulamanın yeni bir sürümü mevcut. Devam etmek için lütfen güncelleyin."
        : "Sürüm güncel.",
]);
