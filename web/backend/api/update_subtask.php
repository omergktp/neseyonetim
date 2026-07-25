<?php
// backend/api/update_subtask.php
// Bir görevin checklist maddesinin (alt görev) yapıldı/yapılmadı durumunu günceller.
// Sahada personel görev adımlarını tek tek işaretledikçe çağrılır.

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

if (!isset($data->alt_gorev_id) || !isset($data->yapildi)) {
    http_response_code(400);
    echo json_encode(["message" => "Eksik bilgi. (alt_gorev_id, yapildi gerekli)"]);
    exit;
}

$alt_gorev_id = (int)$data->alt_gorev_id;
$yapildi = ($data->yapildi === true || $data->yapildi === 1 || $data->yapildi === '1') ? 1 : 0;

// KURAL 1 + sahiplik: alt görev bu firmaya ait VE bağlı olduğu iş emri bu personele mi atanmış?
$q = $db->prepare("
    SELECT ag.id, ie.durum
    FROM is_emirleri_alt_gorevler ag
    JOIN is_emirleri ie ON ag.is_emri_id = ie.id
    WHERE ag.id = :id AND ag.firma_id = :firma_id AND ie.personel_id = :personel_id
    LIMIT 1
");
$q->execute([':id' => $alt_gorev_id, ':firma_id' => $firma_id, ':personel_id' => $personel_id]);
$row = $q->fetch(PDO::FETCH_ASSOC);

if (!$row) {
    http_response_code(404);
    echo json_encode(["message" => "Adım bulunamadı veya size ait değil."]);
    exit;
}

if (in_array($row['durum'], ['tamamlandi', 'iptal'], true)) {
    http_response_code(409);
    echo json_encode(["message" => "Bu görev kapatılmış; adımlar güncellenemez."]);
    exit;
}

$upd = $db->prepare("UPDATE is_emirleri_alt_gorevler SET yapildi_mi = :y
                     WHERE id = :id AND firma_id = :firma_id");
$upd->execute([':y' => $yapildi, ':id' => $alt_gorev_id, ':firma_id' => $firma_id]);

http_response_code(200);
echo json_encode(["message" => "Adım güncellendi.", "yapildi_mi" => $yapildi]);
