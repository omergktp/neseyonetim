<?php
// backend/api/get_sites.php
// Mobil: giriş yapan personelin firmasındaki tesisleri döndürür (arıza bildirimi için seçim listesi).

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once '../config.php';
require_once '../core/Database.php';
require_once '../core/AuthMiddleware.php';

$kullanici = AuthMiddleware::authenticate();
$db = (new Database())->getConnection();

$stmt = $db->prepare("SELECT id, ad FROM siteler WHERE firma_id = :fid AND aktif = 1 ORDER BY ad ASC");
$stmt->bindValue(':fid', $kullanici->firma_id);
$stmt->execute();

http_response_code(200);
echo json_encode(["data" => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
