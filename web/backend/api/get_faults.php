<?php
// backend/api/get_faults.php
// Mobil: giriş yapan TEKNİK personele atanmış açık arızaları döndürür.

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once '../config.php';
require_once '../core/Database.php';
require_once '../core/AuthMiddleware.php';

$kullanici = AuthMiddleware::authenticate();
$db = (new Database())->getConnection();

$firma_id = $kullanici->firma_id;
$personel_id = $kullanici->personel_id;

// KURAL 1: firma_id + bu teknik personele atanmış, açık/bekleyen arızalar
$query = "
    SELECT
        a.id, a.baslik, a.aciklama, a.teknik_notu, a.durum, a.fotograf_url, a.olusturma_tarihi,
        s.id AS site_id, s.ad AS site_adi, s.adres AS site_adresi
    FROM arizalar a
    LEFT JOIN siteler s ON a.site_id = s.id
    WHERE a.firma_id = :firma_id
      AND a.teknik_personel_id = :personel_id
      AND a.durum IN ('acik', 'bekliyor')
    ORDER BY a.olusturma_tarihi DESC
";
$stmt = $db->prepare($query);
$stmt->bindValue(':firma_id', $firma_id);
$stmt->bindValue(':personel_id', $personel_id);
$stmt->execute();

$data = $stmt->fetchAll(PDO::FETCH_ASSOC);

http_response_code(200);
echo json_encode([
    "message" => "Arızalar getirildi.",
    "toplam" => count($data),
    "data" => $data,
]);
