<?php
// backend/api/admin/ariza_guncelle.php
// POST -> bir arızayı günceller (durum/teknik/başlık/açıklama/tesis) veya siler.
// Body: { id, durum?, teknik_personel_id?, baslik?, aciklama?, site_id? }
//    veya { id, islem: 'sil' }

require_once __DIR__ . '/../../core/bootstrap.php';
cors();

$user = require_admin();
$firma_id = $user->firma_id;
$db = (new Database())->getConnection();

$data = read_json_body();
if (!isset($data->id)) {
    json_out(400, ["message" => "Eksik bilgi. (id gerekli)"]);
}
$id = (int)$data->id;

// Arıza bu firmaya mı ait?
$q = $db->prepare("SELECT id, baslik FROM arizalar WHERE id = :id AND firma_id = :fid LIMIT 1");
$q->execute([':id' => $id, ':fid' => $firma_id]);
$ariza = $q->fetch(PDO::FETCH_ASSOC);
if (!$ariza) {
    json_out(404, ["message" => "Arıza bulunamadı."]);
}

// Silme
if (isset($data->islem) && $data->islem === 'sil') {
    // Bağlı masraflar FK ON DELETE CASCADE ile birlikte silinir.
    $del = $db->prepare("DELETE FROM arizalar WHERE id = :id AND firma_id = :fid");
    $del->execute([':id' => $id, ':fid' => $firma_id]);
    log_action($db, $user, 'ariza_sil', 'ariza', $id, $ariza['baslik'] ?? null);
    json_out(200, ["message" => "Arıza kaydı silindi."]);
}

$set = [];
$params = [':id' => $id, ':fid' => $firma_id];
$atanan_teknik = null;

// Başlık / açıklama düzenle
if (isset($data->baslik) && trim($data->baslik) !== '') {
    $set[] = "baslik = :baslik";
    $params[':baslik'] = trim($data->baslik);
}
if (isset($data->aciklama)) {
    $set[] = "aciklama = :aciklama";
    $params[':aciklama'] = trim($data->aciklama);
}

// Tesis değiştir (firmaya ait mi doğrula)
if (isset($data->site_id) && $data->site_id !== '') {
    $sid = (int)$data->site_id;
    $sk = $db->prepare("SELECT id FROM siteler WHERE id = :sid AND firma_id = :fid");
    $sk->execute([':sid' => $sid, ':fid' => $firma_id]);
    if (!$sk->fetch()) {
        json_out(422, ["message" => "Seçilen tesis firmanıza ait değil."]);
    }
    $set[] = "site_id = :site_id";
    $params[':site_id'] = $sid;
}

// Durum güncelle
if (isset($data->durum)) {
    if (!in_array($data->durum, ['acik', 'bekliyor', 'cozuldu', 'iptal', 'dis_destek'], true)) {
        json_out(400, ["message" => "Geçersiz durum."]);
    }
    $set[] = "durum = :durum";
    $params[':durum'] = $data->durum;
    // Çözüldüyse çözüm tarihini yaz
    if ($data->durum === 'cozuldu') {
        $set[] = "cozum_tarihi = NOW()";
    }
}

// Teknik personel ata veya atamayı kaldır.
// Boş string/null gönderilirse atama KALDIRILIR (teknik_personel_id = NULL);
// alan hiç gönderilmezse dokunulmaz.
if (property_exists($data, 'teknik_personel_id')) {
    if ($data->teknik_personel_id === '' || $data->teknik_personel_id === null) {
        $set[] = "teknik_personel_id = NULL";
    } else {
        $tid = (int)$data->teknik_personel_id;
        $kontrol = $db->prepare("SELECT id FROM personeller WHERE id = :tid AND firma_id = :fid AND rol = 'teknik'");
        $kontrol->execute([':tid' => $tid, ':fid' => $firma_id]);
        if (!$kontrol->fetch()) {
            json_out(422, ["message" => "Seçilen kişi firmanıza ait bir teknik personel değil."]);
        }
        $set[] = "teknik_personel_id = :tid";
        $params[':tid'] = $tid;
        $atanan_teknik = $tid;
    }
}

if (empty($set)) {
    json_out(400, ["message" => "Güncellenecek alan yok."]);
}

$sql = "UPDATE arizalar SET " . implode(', ', $set) . " WHERE id = :id AND firma_id = :fid";
$stmt = $db->prepare($sql);
$stmt->execute($params);

// Teknik atandıysa ona bildirim gönder
if ($atanan_teknik !== null) {
    try {
        require_once __DIR__ . '/../../core/FcmSender.php';
        $t = $db->prepare("SELECT fcm_token FROM personeller WHERE id = :pid AND firma_id = :fid");
        $t->execute([':pid' => $atanan_teknik, ':fid' => $firma_id]);
        $fcm = $t->fetchColumn();
        if (!empty($fcm)) {
            FcmSender::send($fcm, 'Yeni Arıza Atandı', $ariza['baslik'], [
                'tip' => 'ariza',
                'ariza_id' => (string)$id,
            ]);
        }
    } catch (Throwable $e) { /* bildirim opsiyonel */ }
}

log_action($db, $user, 'ariza_guncelle', 'ariza', $id,
    (isset($data->durum) ? "durum: {$data->durum}" : null) .
    ($atanan_teknik !== null ? " teknik atandı: $atanan_teknik" : ''));
json_out(200, ["message" => "Arıza güncellendi."]);
