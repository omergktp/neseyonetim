<?php
// backend/api/get_tasks.php

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once '../config.php';
require_once '../core/Database.php';
require_once '../core/AuthMiddleware.php';

// Token doğrulama (Sadece giriş yapmış kullanıcılar erişebilir)
$kullanici = AuthMiddleware::authenticate();

$database = new Database();
$db = $database->getConnection();

// KURAL 1: Multi-Tenant gereği firma_id her zaman kullanılmalı
$firma_id = $kullanici->firma_id;
$personel_id = $kullanici->personel_id;

// Personelin kendi görevlerini getiren sorgu
$query = "
    SELECT 
        ie.id, ie.baslik, ie.aciklama, ie.durum, ie.qr_kod, ie.planlanan_baslangic_tarihi,
        s.ad as site_adi, s.adres as site_adresi, s.enlem, s.boylam
    FROM is_emirleri ie
    LEFT JOIN siteler s ON ie.site_id = s.id
    WHERE ie.firma_id = :firma_id 
    AND ie.personel_id = :personel_id 
    AND ie.durum IN ('bekliyor', 'devam_ediyor')
    ORDER BY ie.planlanan_baslangic_tarihi ASC
";

$stmt = $db->prepare($query);
$stmt->bindParam(':firma_id', $firma_id);
$stmt->bindParam(':personel_id', $personel_id);
$stmt->execute();

$tasks = [];
while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    // Alt görevleri (Checklist) çek
    $sub_query = "SELECT id, gorev_metni, yapildi_mi FROM is_emirleri_alt_gorevler WHERE is_emri_id = :is_emri_id AND firma_id = :firma_id";
    $sub_stmt = $db->prepare($sub_query);
    $sub_stmt->bindParam(':is_emri_id', $row['id']);
    $sub_stmt->bindParam(':firma_id', $firma_id);
    $sub_stmt->execute();
    
    $row['alt_gorevler'] = $sub_stmt->fetchAll(PDO::FETCH_ASSOC);
    $tasks[] = $row;
}

http_response_code(200);
echo json_encode([
    "message" => "Görevler başarıyla getirildi.",
    "toplam_gorev" => count($tasks),
    "data" => $tasks
]);
