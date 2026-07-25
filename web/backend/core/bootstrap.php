<?php
// backend/core/bootstrap.php
// Tüm admin API uçlarının ortak başlangıç dosyası:
// CORS başlıkları + OPTIONS preflight + yardımcı fonksiyonlar + yetki kontrolü.

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/Database.php';
require_once __DIR__ . '/AuthMiddleware.php';

// CORS başlıklarını gönderir ve tarayıcının preflight (OPTIONS) isteğini yanıtlar.
// Not: Authorization başlığı taşıyan fetch istekleri tarayıcıda önce OPTIONS atar;
// bu yanıtlanmazsa web panelden yapılan istekler başarısız olur.
function cors() {
    header("Access-Control-Allow-Origin: *");
    header("Content-Type: application/json; charset=UTF-8");
    header("Access-Control-Allow-Methods: GET, POST, PUT, OPTIONS");
    header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With");
    header("Access-Control-Max-Age: 3600");

    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
}

// JSON yanıt döndürüp script'i sonlandırır.
function json_out($code, $payload) {
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

// Sadece giriş yapmış yöneticilerin erişmesini sağlar. Doğrulanmış kullanıcıyı döndürür.
function require_admin() {
    $user = AuthMiddleware::authenticate();
    if (!isset($user->rol) || $user->rol !== 'yonetici') {
        json_out(403, ["message" => "Bu işlem için yönetici yetkisi gereklidir."]);
    }
    return $user;
}

// POST gövdesini JSON olarak okur (boşsa boş nesne döner).
function read_json_body() {
    $raw = file_get_contents("php://input");
    $data = json_decode($raw);
    return $data ?: new stdClass();
}

// Denetim izi (audit log): "kim, ne zaman, neyi yaptı" kaydı.
// Log yazılamaması asıl işlemi ASLA bozmamalı — hatalar sessizce yutulur.
function log_action(PDO $db, $user, string $eylem, ?string $hedefTip = null, ?int $hedefId = null, ?string $detay = null): void {
    try {
        $stmt = $db->prepare("INSERT INTO audit_log (firma_id, personel_id, eylem, hedef_tip, hedef_id, detay, ip)
                              VALUES (:fid, :pid, :eylem, :htip, :hid, :detay, :ip)");
        $stmt->execute([
            ':fid'   => $user->firma_id,
            ':pid'   => $user->personel_id ?? null,
            ':eylem' => $eylem,
            ':htip'  => $hedefTip,
            ':hid'   => $hedefId,
            ':detay' => $detay,
            ':ip'    => $_SERVER['REMOTE_ADDR'] ?? null,
        ]);
    } catch (Throwable $e) { /* loglama asıl işlemi engellemesin */ }
}
