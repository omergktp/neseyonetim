<?php
// backend/api/start_task.php
// Görevi başlatır (durum: bekliyor -> devam_ediyor).
// Doğrulama: 'qr' (QR kodu görevin qr_kod'u ile eşleşmeli) veya 'konum' (sahada olma, mobilde 50m kontrolü yapılır).

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once '../config.php';
require_once '../core/Database.php';
require_once '../core/AuthMiddleware.php';

$kullanici = AuthMiddleware::authenticate();

$database = new Database();
$db = $database->getConnection();

$firma_id = $kullanici->firma_id;
$personel_id = $kullanici->personel_id;

$data = json_decode(file_get_contents("php://input"));

if (!isset($data->is_emri_id) || !isset($data->yontem)) {
    http_response_code(400);
    echo json_encode(["message" => "Eksik bilgi. (is_emri_id, yontem gerekli)"]);
    exit;
}

$is_emri_id = (int)$data->is_emri_id;
$yontem = $data->yontem;

if (!in_array($yontem, ['qr', 'konum'], true)) {
    http_response_code(400);
    echo json_encode(["message" => "Geçersiz yöntem. (qr veya konum)"]);
    exit;
}

// KURAL 1: Görev gerçekten bu firmaya ve bu personele mi ait?
// Sitenin QR'ını da çek: tesise asılan QR tüm görevleri doğrulayabilir.
$q = $db->prepare("SELECT ie.id, ie.durum, ie.qr_kod, s.qr_kod AS site_qr_kod, s.enlem AS site_enlem, s.boylam AS site_boylam
                   FROM is_emirleri ie
                   LEFT JOIN siteler s ON ie.site_id = s.id
                   WHERE ie.id = :id AND ie.firma_id = :firma_id AND ie.personel_id = :personel_id LIMIT 1");
$q->execute([':id' => $is_emri_id, ':firma_id' => $firma_id, ':personel_id' => $personel_id]);
$gorev = $q->fetch(PDO::FETCH_ASSOC);

if (!$gorev) {
    http_response_code(404);
    echo json_encode(["message" => "Görev bulunamadı veya size ait değil."]);
    exit;
}

if (in_array($gorev['durum'], ['tamamlandi', 'iptal'], true)) {
    http_response_code(409);
    echo json_encode(["message" => "Bu görev zaten kapatılmış."]);
    exit;
}

// QR yöntemi: okutulan kod, görevin kendi qr_kod'u VEYA görevin tesisinin qr_kod'u ile eşleşmeli.
if ($yontem === 'qr') {
    $gecerliKodlar = array_values(array_filter([$gorev['qr_kod'], $gorev['site_qr_kod']]));
    if (empty($gecerliKodlar)) {
        http_response_code(422);
        echo json_encode(["message" => "Bu görev veya tesis için QR tanımlı değil. Lütfen 'Konumla Başlat' seçeneğini kullanın."]);
        exit;
    }
    $qr_deger = isset($data->qr_deger) ? trim($data->qr_deger) : '';
    if ($qr_deger === '' || !in_array($qr_deger, $gecerliKodlar, true)) {
        http_response_code(422);
        echo json_encode(["message" => "Okutulan QR kodu bu görevin tesisine ait değil."]);
        exit;
    }
}
// 'konum' yöntemi: sahada olma doğrulaması artık SUNUCUDA da yapılır (mobil 50m kontrolüne
// güvenilemez; istemci değiştirilebilir). Tesisin koordinatı tanımlıysa istemci konum
// göndermek zorundadır ve mesafe sınırı aşılırsa başlatma reddedilir.
if ($yontem === 'konum') {
    $siteLat = $gorev['site_enlem'];
    $siteLng = $gorev['site_boylam'];
    if ($siteLat !== null && $siteLng !== null && (float)$siteLat != 0.0 && (float)$siteLng != 0.0) {
        if (!isset($data->enlem, $data->boylam) || !is_numeric($data->enlem) || !is_numeric($data->boylam)) {
            http_response_code(422);
            echo json_encode(["message" => "Konumla başlatmak için konum verisi gerekli. Lütfen uygulamayı güncelleyin."]);
            exit;
        }
        // Haversine (metre)
        $lat1 = deg2rad((float)$data->enlem);  $lng1 = deg2rad((float)$data->boylam);
        $lat2 = deg2rad((float)$siteLat);      $lng2 = deg2rad((float)$siteLng);
        $a = sin(($lat2 - $lat1) / 2) ** 2 + cos($lat1) * cos($lat2) * sin(($lng2 - $lng1) / 2) ** 2;
        $mesafe = 6371000 * 2 * atan2(sqrt($a), sqrt(1 - $a));
        // İstemci 50m uygular; sunucu GPS sapması payıyla 100m'ye kadar tolere eder.
        if ($mesafe > 100) {
            http_response_code(422);
            echo json_encode(["message" => "Tesise yeterince yakın değilsiniz (ölçülen: " . round($mesafe) . " m)."]);
            exit;
        }
    }
    // Tesis koordinatı tanımlı değilse mesafe doğrulanamaz; veri girişi eksikliği
    // görevi engellememeli (yönetici panelden koordinat girmelidir).
}

$upd = $db->prepare("UPDATE is_emirleri SET durum = 'devam_ediyor'
                     WHERE id = :id AND firma_id = :firma_id AND personel_id = :personel_id
                     AND durum IN ('bekliyor', 'devam_ediyor')");
$upd->execute([':id' => $is_emri_id, ':firma_id' => $firma_id, ':personel_id' => $personel_id]);

// Hiç satır güncellenmediyse (durum SELECT ile UPDATE arasında değişmiş olabilir): başlatma başarısız.
if ($upd->rowCount() === 0) {
    http_response_code(409);
    echo json_encode(["message" => "Görev başlatılamadı (durumu değişmiş olabilir)."]);
    exit;
}

http_response_code(200);
echo json_encode(["message" => "Görev başlatıldı.", "durum" => "devam_ediyor"]);
