<?php
// backend/api/update_fault.php
// Mobil: teknik personel, kendisine atanmış arızanın durumunu günceller.
// Body: { ariza_id, durum: 'cozuldu' | 'bekliyor', not?: string }
//  - 'cozuldu'  -> arıza kapatılır (cozum_tarihi yazılır)
//  - 'bekliyor' -> malzeme/parça bekliyor (açık kalır, not ile açıklanır)

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

if (!isset($data->ariza_id, $data->durum)) {
    http_response_code(400);
    echo json_encode(["message" => "ariza_id ve durum gerekli."]);
    exit;
}

// Teknik personelin çekebileceği durumlar: çözüldü, malzeme bekliyor, dış destek gerekli
if (!in_array($data->durum, ['cozuldu', 'bekliyor', 'dis_destek'], true)) {
    http_response_code(400);
    echo json_encode(["message" => "Geçersiz durum."]);
    exit;
}

$ariza_id = (int)$data->ariza_id;
$durum = $data->durum;
$not = isset($data->not) ? trim($data->not) : null;

$params = [
    ':durum' => $durum,
    ':not' => $not,
    ':id' => $ariza_id,
    ':fid' => $firma_id,
    ':pid' => $personel_id,
];
$extraSet = "";

// Çözüldüyse: çözüm fotoğrafı ZORUNLU + çözüm tarihi yazılır
if ($durum === 'cozuldu') {
    if (!isset($data->cozum_fotograf) || $data->cozum_fotograf === '') {
        http_response_code(400);
        echo json_encode(["message" => "Çözüm fotoğrafı gerekli."]);
        exit;
    }
    $cozum_foto_url = save_base64_image($data->cozum_fotograf, 'fault_resolutions');
    if ($cozum_foto_url === null) {
        http_response_code(400);
        echo json_encode(["message" => "Çözüm fotoğrafı kaydedilemedi (geçersiz görsel)."]);
        exit;
    }
    $extraSet = ", cozum_tarihi = NOW(), cozum_fotograf_url = :cfoto";
    $params[':cfoto'] = $cozum_foto_url;
}

// KURAL 1: Sadece kendi firmasında, kendisine atanmış arızayı günceller.
// Zaten 'cozuldu' olan arıza mobilden tekrar açılamaz (yalnızca yönetici panelden değiştirebilir).
$stmt = $db->prepare("UPDATE arizalar
                      SET durum = :durum, teknik_notu = :not $extraSet
                      WHERE id = :id AND firma_id = :fid AND teknik_personel_id = :pid
                        AND durum <> 'cozuldu'");
$stmt->execute($params);

if ($stmt->rowCount() > 0) {
    $mesajlar = [
        'cozuldu'    => "Arıza çözüldü olarak kapatıldı.",
        'bekliyor'   => "Arıza 'malzeme bekliyor' olarak güncellendi.",
        'dis_destek' => "Arıza 'dış destek gerekli' olarak yöneticiye iletildi.",
    ];
    http_response_code(200);
    echo json_encode(["message" => $mesajlar[$durum] ?? "Arıza güncellendi."]);
} else {
    http_response_code(400);
    echo json_encode(["message" => "Arıza güncellenemedi (size ait değil veya zaten çözülmüş)."]);
}
