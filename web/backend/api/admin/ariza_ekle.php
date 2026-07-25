<?php
// backend/api/admin/ariza_ekle.php
// POST -> Yönetici manuel arıza oluşturur ve isteğe bağlı teknik personele atar.
// Body: { site_id, baslik, aciklama?, teknik_personel_id? }

require_once __DIR__ . '/../../core/bootstrap.php';
cors();

$user = require_admin();
$firma_id = $user->firma_id;
$admin_id = $user->personel_id;
$db = (new Database())->getConnection();

$data = read_json_body();

if (!isset($data->site_id, $data->baslik) || trim($data->baslik) === '') {
    json_out(400, ["message" => "Eksik bilgi. (site_id, baslik gerekli)"]);
}

$site_id = (int)$data->site_id;
$baslik = trim($data->baslik);
$aciklama = isset($data->aciklama) ? trim($data->aciklama) : null;
$oncelik = (isset($data->oncelik) && in_array($data->oncelik, ['dusuk', 'normal', 'yuksek'], true))
            ? $data->oncelik : 'normal';

// KURAL 1: Site bu firmaya mı ait?
$kontrol = $db->prepare("SELECT id FROM siteler WHERE id = :sid AND firma_id = :fid");
$kontrol->execute([':sid' => $site_id, ':fid' => $firma_id]);
if (!$kontrol->fetch()) {
    json_out(422, ["message" => "Seçilen tesis firmanıza ait değil."]);
}

// Teknik personel (opsiyonel) — firmaya ait ve teknik rolde mi?
$teknik_id = null;
if (isset($data->teknik_personel_id) && $data->teknik_personel_id !== '') {
    $teknik_id = (int)$data->teknik_personel_id;
    $tk = $db->prepare("SELECT id FROM personeller WHERE id = :tid AND firma_id = :fid AND rol = 'teknik'");
    $tk->execute([':tid' => $teknik_id, ':fid' => $firma_id]);
    if (!$tk->fetch()) {
        json_out(422, ["message" => "Seçilen kişi firmanıza ait bir teknik personel değil."]);
    }
}

// bildiren_personel_id NOT NULL: yönetici kaydı bildiren olarak yazılır
$stmt = $db->prepare("
    INSERT INTO arizalar (firma_id, site_id, bildiren_personel_id, teknik_personel_id, baslik, aciklama, durum, oncelik)
    VALUES (:firma_id, :site_id, :bildiren, :teknik, :baslik, :aciklama, 'acik', :oncelik)
");
$stmt->execute([
    ':firma_id' => $firma_id,
    ':site_id' => $site_id,
    ':bildiren' => $admin_id,
    ':teknik' => $teknik_id,
    ':baslik' => $baslik,
    ':aciklama' => $aciklama,
    ':oncelik' => $oncelik,
]);
$yeni_id = (int)$db->lastInsertId();

// Teknik atandıysa bildirim gönder
if ($teknik_id !== null) {
    try {
        require_once __DIR__ . '/../../core/FcmSender.php';
        $t = $db->prepare("SELECT fcm_token FROM personeller WHERE id = :pid AND firma_id = :fid");
        $t->execute([':pid' => $teknik_id, ':fid' => $firma_id]);
        $fcm = $t->fetchColumn();
        if (!empty($fcm)) {
            FcmSender::send($fcm, 'Yeni Arıza Atandı', $baslik, ['tip' => 'ariza', 'ariza_id' => (string)$yeni_id]);
        }
    } catch (Throwable $e) { /* bildirim opsiyonel */ }
}

log_action($db, $user, 'ariza_ekle', 'ariza', $yeni_id);
json_out(201, ["message" => "Arıza oluşturuldu.", "id" => $yeni_id]);
