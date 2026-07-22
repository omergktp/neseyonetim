<?php
// backend/api/clear_fcm_token.php
// Çıkışta çağrılır: giriş yapan personelin FCM token'ını siler (bu cihaza artık bildirim gitmez).

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once '../config.php';
require_once '../core/Database.php';
require_once '../core/AuthMiddleware.php';

$kullanici = AuthMiddleware::authenticate();

$db = (new Database())->getConnection();

$firma_id = $kullanici->firma_id;
$personel_id = $kullanici->personel_id;

$stmt = $db->prepare("UPDATE personeller SET fcm_token = NULL
                      WHERE id = :pid AND firma_id = :fid");
$stmt->execute([':pid' => $personel_id, ':fid' => $firma_id]);

http_response_code(200);
echo json_encode(["message" => "Bildirim aboneliği kaldırıldı."]);
