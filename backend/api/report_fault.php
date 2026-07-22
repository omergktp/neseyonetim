<?php
// backend/api/report_fault.php
// Saha personeli arıza bildirir (başlık, açıklama, site, foto). durum='acik' olarak kaydedilir.

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once '../config.php';
require_once '../core/Database.php';
require_once '../core/AuthMiddleware.php';
require_once '../core/upload.php';

$kullanici = AuthMiddleware::authenticate();
$db = (new Database())->getConnection();

$firma_id = $kullanici->firma_id;
$personel_id = $kullanici->personel_id;

$data = json_decode(file_get_contents("php://input"));

if (!isset($data->site_id, $data->baslik) || trim($data->baslik) === '') {
    http_response_code(400);
    echo json_encode(["message" => "Eksik bilgi. (site_id, baslik gerekli)"]);
    exit;
}

$site_id = (int)$data->site_id;
$baslik = trim($data->baslik);
$aciklama = isset($data->aciklama) ? trim($data->aciklama) : null;

// KURAL 1: Site bu firmaya mı ait?
$kontrol = $db->prepare("SELECT id FROM siteler WHERE id = :sid AND firma_id = :fid");
$kontrol->execute([':sid' => $site_id, ':fid' => $firma_id]);
if (!$kontrol->fetch()) {
    http_response_code(422);
    echo json_encode(["message" => "Geçersiz tesis."]);
    exit;
}

// Foto (opsiyonel) base64 -> dosya
$foto_url = null;
if (isset($data->fotograf_url) && $data->fotograf_url !== '') {
    $foto_url = save_base64_image($data->fotograf_url, 'faults');
    if ($foto_url === null) {
        http_response_code(400);
        echo json_encode(["message" => "Arıza fotoğrafı kaydedilemedi."]);
        exit;
    }
}

$stmt = $db->prepare("
    INSERT INTO arizalar (firma_id, site_id, bildiren_personel_id, baslik, aciklama, fotograf_url, durum)
    VALUES (:firma_id, :site_id, :bildiren, :baslik, :aciklama, :foto, 'acik')
");
$stmt->execute([
    ':firma_id' => $firma_id,
    ':site_id' => $site_id,
    ':bildiren' => $personel_id,
    ':baslik' => $baslik,
    ':aciklama' => $aciklama,
    ':foto' => $foto_url,
]);

http_response_code(201);
echo json_encode(["message" => "Arıza bildirimi alındı.", "id" => (int)$db->lastInsertId()]);
