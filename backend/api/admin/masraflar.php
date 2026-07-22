<?php
// backend/api/admin/masraflar.php
// GET  -> firmaya ait masraf/malzeme taleplerini listeler (opsiyonel ?durum= filtresi)
// POST -> bir masrafı onaylar veya reddeder { id, islem: 'onayla' | 'reddet' }

require_once __DIR__ . '/../../core/bootstrap.php';
cors();

$user = require_admin();
$firma_id = $user->firma_id;
$db = (new Database())->getConnection();

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    $durum = $_GET['durum'] ?? null;

    $sql = "
        SELECT
            mt.id, mt.kalem_adi, mt.tutar, mt.durum, mt.fis_fatura_fotograf, mt.olusturma_tarihi,
            p.ad_soyad AS personel_adi, p.rol AS personel_rol,
            ie.baslik AS is_emri_baslik,
            ar.baslik AS ariza_baslik,
            COALESCE(sie.ad, sar.ad) AS site_adi
        FROM malzeme_talepleri mt
        LEFT JOIN personeller p ON mt.personel_id = p.id
        LEFT JOIN is_emirleri ie ON mt.is_emri_id = ie.id
        LEFT JOIN arizalar ar    ON mt.ariza_id = ar.id
        LEFT JOIN siteler sie    ON ie.site_id = sie.id
        LEFT JOIN siteler sar    ON ar.site_id = sar.id
        WHERE mt.firma_id = :firma_id
    ";
    $params = [':firma_id' => $firma_id];

    if ($durum !== null && in_array($durum, ['bekliyor', 'onaylandi', 'reddedildi'], true)) {
        $sql .= " AND mt.durum = :durum";
        $params[':durum'] = $durum;
    }
    // Belirli bir arıza veya iş emrine bağlı masrafları filtrele
    if (isset($_GET['ariza_id']) && $_GET['ariza_id'] !== '') {
        $sql .= " AND mt.ariza_id = :aid";
        $params[':aid'] = (int)$_GET['ariza_id'];
    }
    if (isset($_GET['is_emri_id']) && $_GET['is_emri_id'] !== '') {
        $sql .= " AND mt.is_emri_id = :ieid";
        $params[':ieid'] = (int)$_GET['is_emri_id'];
    }
    $sql .= " ORDER BY mt.olusturma_tarihi DESC";

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    json_out(200, ["data" => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
}

if ($method === 'POST') {
    $data = read_json_body();

    if (!isset($data->id, $data->islem)) {
        json_out(400, ["message" => "Eksik bilgi. (id, islem gerekli)"]);
    }
    $id = (int)$data->id;
    $islem = $data->islem;

    // Silme (KURAL 1: sadece kendi firmasının masrafı)
    if ($islem === 'sil') {
        $del = $db->prepare("DELETE FROM malzeme_talepleri WHERE id = :id AND firma_id = :fid");
        $del->execute([':id' => $id, ':fid' => $firma_id]);
        if ($del->rowCount() === 0) {
            json_out(404, ["message" => "Masraf bulunamadı."]);
        }
        log_action($db, $user, 'masraf_sil', 'masraf', $id);
        json_out(200, ["message" => "Masraf silindi."]);
    }

    $yeni_durum = $islem === 'onayla' ? 'onaylandi' : ($islem === 'reddet' ? 'reddedildi' : null);
    if ($yeni_durum === null) {
        json_out(400, ["message" => "Geçersiz işlem. (onayla veya reddet)"]);
    }

    // KURAL 1: Sadece kendi firmasının masrafını günceller
    $stmt = $db->prepare("UPDATE malzeme_talepleri SET durum = :durum
                          WHERE id = :id AND firma_id = :fid");
    $stmt->execute([':durum' => $yeni_durum, ':id' => $id, ':fid' => $firma_id]);

    if ($stmt->rowCount() === 0) {
        json_out(404, ["message" => "Masraf bulunamadı veya zaten güncellenmiş."]);
    }
    log_action($db, $user, 'masraf_' . $islem, 'masraf', $id, "yeni durum: $yeni_durum");
    json_out(200, ["message" => $yeni_durum === 'onaylandi' ? "Masraf onaylandı." : "Masraf reddedildi."]);
}

json_out(405, ["message" => "Desteklenmeyen metot."]);
