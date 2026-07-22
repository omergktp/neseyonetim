<?php
// backend/api/save_task.php

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once '../config.php';
require_once '../core/Database.php';
require_once '../core/AuthMiddleware.php';
require_once '../core/upload.php';

// Token doğrulama
$kullanici = AuthMiddleware::authenticate();

$database = new Database();
$db = $database->getConnection();

$firma_id = $kullanici->firma_id;
$personel_id = $kullanici->personel_id;

$data = json_decode(file_get_contents("php://input"));

if (isset($data->is_emri_id) && isset($data->tamamlanma_enlem) && isset($data->tamamlanma_boylam)) {
    // Koordinatlar sayısal olmalı (DB'ye çöp veri girmesin).
    if (!is_numeric($data->tamamlanma_enlem) || !is_numeric($data->tamamlanma_boylam)) {
        http_response_code(400);
        echo json_encode(["message" => "Koordinatlar sayısal olmalı."]);
        exit;
    }
    $is_emri_id = (int)$data->is_emri_id;
    $enlem = (float)$data->tamamlanma_enlem;
    $boylam = (float)$data->tamamlanma_boylam;
    
    // Fotoğraf base64 olarak gelir; sunucuda dosyaya yazılıp DB'ye yolu kaydedilir.
    $fotograf_url = null;
    if (isset($data->kapanis_fotograf_url) && $data->kapanis_fotograf_url !== '') {
        $fotograf_url = save_base64_image($data->kapanis_fotograf_url, 'tasks');
        if ($fotograf_url === null) {
            http_response_code(400);
            echo json_encode(["message" => "Kapanış fotoğrafı kaydedilemedi (geçersiz görsel)."]);
            exit;
        }
    }

    // KURAL 1: Multi-Tenant kuralı işletiliyor. Yetkisiz güncellemeyi önlemek için firma_id ve personel_id şartı!
    // Yalnızca aktif (bekliyor/devam_ediyor) görev tamamlanabilir; iptal/zaten-tamamlanmış engellenir.
    $query = "UPDATE is_emirleri
              SET durum = 'tamamlandi',
                  tamamlanma_tarihi = NOW(),
                  tamamlanma_enlem = :enlem,
                  tamamlanma_boylam = :boylam,
                  kapanis_fotograf_url = :fotograf_url
              WHERE id = :is_emri_id AND firma_id = :firma_id AND personel_id = :personel_id
                AND durum IN ('bekliyor', 'devam_ediyor')";
              
    $stmt = $db->prepare($query);
    $stmt->bindParam(':enlem', $enlem);
    $stmt->bindParam(':boylam', $boylam);
    $stmt->bindParam(':fotograf_url', $fotograf_url);
    $stmt->bindParam(':is_emri_id', $is_emri_id);
    $stmt->bindParam(':firma_id', $firma_id);
    $stmt->bindParam(':personel_id', $personel_id);

    if ($stmt->execute()) {
        if ($stmt->rowCount() > 0) {
            http_response_code(200);
            echo json_encode(["message" => "Görev başarıyla tamamlandı ve kaydedildi."]);
        } else {
            http_response_code(400);
            echo json_encode(["message" => "Görev güncellenemedi. Görev bulunamadı veya size ait değil."]);
        }
    } else {
        http_response_code(503);
        echo json_encode(["message" => "Veritabanı hatası oluştu."]);
    }
} else {
    http_response_code(400);
    echo json_encode(["message" => "Eksik bilgi gönderildi. (is_emri_id, tamamlanma_enlem, tamamlanma_boylam gerekli)"]);
}
