<?php
// backend/api/save_fcm_token.php
// Mobil uygulama, giriş sonrası aldığı FCM cihaz token'ını buraya kaydeder.

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once '../config.php';
require_once '../core/Database.php';
require_once '../core/AuthMiddleware.php';

$kullanici = AuthMiddleware::authenticate();

$db = (new Database())->getConnection();

$data = json_decode(file_get_contents("php://input"));

if (!isset($data->fcm_token) || trim($data->fcm_token) === '') {
    http_response_code(400);
    echo json_encode(["message" => "fcm_token gerekli."]);
    exit;
}

$fcm_token = trim($data->fcm_token);
$firma_id = $kullanici->firma_id;
$personel_id = $kullanici->personel_id;

// Token benzersizliği: bu cihaz token'ı başka bir personele bağlıysa oradan temizle.
// (Paylaşılan telefonda farklı kişi giriş yapınca eski kişi bildirim almasın.)
$temizle = $db->prepare("UPDATE personeller SET fcm_token = NULL
                         WHERE fcm_token = :fcm AND id <> :pid");
$temizle->execute([':fcm' => $fcm_token, ':pid' => $personel_id]);

// KURAL 1: Sadece kendi firmasındaki kendi kaydını güncelleyebilir
$stmt = $db->prepare("UPDATE personeller SET fcm_token = :fcm
                      WHERE id = :pid AND firma_id = :fid");
$stmt->execute([':fcm' => $fcm_token, ':pid' => $personel_id, ':fid' => $firma_id]);

http_response_code(200);
echo json_encode(["message" => "FCM token kaydedildi."]);
