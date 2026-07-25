<?php
// backend/api/add_expense.php

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

// Sadece teknik personelin masraf girmesini isteyebiliriz (Kurala göre)
if ($kullanici->rol !== 'teknik' && $kullanici->rol !== 'yonetici') {
    http_response_code(403);
    echo json_encode(["message" => "Bu işlem için sadece Teknik Personel yetkilidir."]);
    exit;
}

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

// Masraf bir iş emrine VEYA bir arızaya bağlanabilir (en az biri gerekli).
$has_is_emri = isset($data->is_emri_id) && $data->is_emri_id !== '';
$has_ariza   = isset($data->ariza_id) && $data->ariza_id !== '';

if (($has_is_emri || $has_ariza) && isset($data->kalem_adi) && isset($data->tutar) && isset($data->fis_fotograf_url)) {
    $firma_id = $kullanici->firma_id;
    $personel_id = $kullanici->personel_id;
    $is_emri_id = $has_is_emri ? (int)$data->is_emri_id : null;
    $ariza_id   = $has_ariza ? (int)$data->ariza_id : null;

    // KURAL 1: Masrafın bağlandığı iş emri/arıza GERÇEKTEN bu firmaya ait mi?
    // (Aksi halde başka firmanın kaydına masraf bağlanıp JOIN üzerinden başlık sızabilir.)
    // Sahiplik: teknik personel yalnızca KENDİSİNE atanmış iş emri/arızaya masraf bağlayabilir.
    // (Yönetici firma içindeki her kayda bağlayabilir.)
    $yonetici = ($kullanici->rol === 'yonetici');
    if ($is_emri_id !== null) {
        $sql = "SELECT 1 FROM is_emirleri WHERE id = :id AND firma_id = :fid";
        $p = [':id' => $is_emri_id, ':fid' => $firma_id];
        if (!$yonetici) { $sql .= " AND personel_id = :pid"; $p[':pid'] = $personel_id; }
        $c = $db->prepare($sql);
        $c->execute($p);
        if (!$c->fetch()) {
            http_response_code(422);
            echo json_encode(["message" => "Geçersiz iş emri (size atanmış değil)."]);
            exit;
        }
    }
    if ($ariza_id !== null) {
        $sql = "SELECT 1 FROM arizalar WHERE id = :id AND firma_id = :fid";
        $p = [':id' => $ariza_id, ':fid' => $firma_id];
        if (!$yonetici) { $sql .= " AND teknik_personel_id = :pid"; $p[':pid'] = $personel_id; }
        $c = $db->prepare($sql);
        $c->execute($p);
        if (!$c->fetch()) {
            http_response_code(422);
            echo json_encode(["message" => "Geçersiz arıza (size atanmış değil)."]);
            exit;
        }
    }

    // Tutar sayısal ve pozitif olmalı
    if (!is_numeric($data->tutar) || (float)$data->tutar <= 0) {
        http_response_code(400);
        echo json_encode(["message" => "Tutar geçerli ve pozitif bir sayı olmalı."]);
        exit;
    }

    $kalem_adi = htmlspecialchars(strip_tags($data->kalem_adi));
    $tutar = (float)$data->tutar;
    // Fiş/fatura fotoğrafı base64 gelir; dosyaya yazılıp yolu saklanır.
    $fotograf_url = save_base64_image($data->fis_fotograf_url, 'expenses');
    if ($fotograf_url === null) {
        http_response_code(400);
        echo json_encode(["message" => "Fiş/fatura fotoğrafı kaydedilemedi (geçersiz görsel)."]);
        exit;
    }

    $query = "INSERT INTO malzeme_talepleri
              (firma_id, personel_id, is_emri_id, ariza_id, kalem_adi, tutar, fis_fatura_fotograf, durum, olusturma_tarihi)
              VALUES
              (:firma_id, :personel_id, :is_emri_id, :ariza_id, :kalem_adi, :tutar, :fotograf_url, 'bekliyor', NOW())";

    $stmt = $db->prepare($query);
    $stmt->bindValue(':firma_id', $firma_id);
    $stmt->bindValue(':personel_id', $personel_id);
    $stmt->bindValue(':is_emri_id', $is_emri_id, $is_emri_id === null ? PDO::PARAM_NULL : PDO::PARAM_INT);
    $stmt->bindValue(':ariza_id', $ariza_id, $ariza_id === null ? PDO::PARAM_NULL : PDO::PARAM_INT);
    $stmt->bindValue(':kalem_adi', $kalem_adi);
    $stmt->bindValue(':tutar', $tutar);
    $stmt->bindValue(':fotograf_url', $fotograf_url);

    if ($stmt->execute()) {
        http_response_code(201);
        echo json_encode(["message" => "Masraf formu başarıyla gönderildi ve onaya sunuldu."]);
    } else {
        http_response_code(503);
        echo json_encode(["message" => "Veritabanı hatası oluştu."]);
    }
} else {
    http_response_code(400);
    echo json_encode(["message" => "Eksik bilgi gönderildi. (is_emri_id veya ariza_id, kalem_adi, tutar, fis_fotograf_url)"]);
}
