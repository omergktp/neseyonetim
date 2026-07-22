<?php
// backend/api/admin/siteler.php
// GET  -> firmaya ait siteleri/tesisleri listeler (QR kodlarıyla)
// POST -> { ...alanlar }                 : yeni site ekler (otomatik QR üretir)
//      -> { id, islem: 'guncelle', ... } : siteyi günceller
//      -> { id, islem: 'sil' }           : siteyi siler (bağlı iş emri/arıza yoksa)
//      -> { id, islem: 'qr_yenile' }     : sitenin QR kodunu yeniden üretir

require_once __DIR__ . '/../../core/bootstrap.php';
cors();

$user = require_admin();
$firma_id = $user->firma_id;
$db = (new Database())->getConnection();

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

// Tesise asılacak benzersiz QR değeri üretir (örn. SAHA-1A2B3C4D5E).
function yeniSiteQr($db) {
    do {
        $kod = 'SAHA-' . strtoupper(bin2hex(random_bytes(5)));
        $c = $db->prepare("SELECT COUNT(*) FROM siteler WHERE qr_kod = :k");
        $c->execute([':k' => $kod]);
    } while ((int)$c->fetchColumn() > 0);
    return $kod;
}

if ($method === 'GET') {
    $stmt = $db->prepare("
        SELECT id, ad, adres, enlem, boylam, qr_kod, aktif, olusturma_tarihi
        FROM siteler
        WHERE firma_id = :firma_id
        ORDER BY ad ASC
    ");
    $stmt->bindParam(':firma_id', $firma_id);
    $stmt->execute();
    json_out(200, ["data" => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
}

if ($method === 'POST') {
    $data = read_json_body();

    // --- Mevcut site üzerinde işlem ---
    if (isset($data->id, $data->islem)) {
        $id = (int)$data->id;
        $islem = $data->islem;

        // Sitenin bu firmaya ait olduğunu doğrula
        $chk = $db->prepare("SELECT id FROM siteler WHERE id = :id AND firma_id = :fid LIMIT 1");
        $chk->execute([':id' => $id, ':fid' => $firma_id]);
        if (!$chk->fetch()) {
            json_out(404, ["message" => "Tesis bulunamadı."]);
        }

        if ($islem === 'sil') {
            // Bağlı iş emri/arıza varsa silme (cascade ile geçmişi yok etmeyi önle).
            $b = $db->prepare("
                SELECT
                    (SELECT COUNT(*) FROM is_emirleri        WHERE site_id = :id1) AS ie,
                    (SELECT COUNT(*) FROM arizalar            WHERE site_id = :id2) AS ar,
                    (SELECT COUNT(*) FROM periyodik_sablonlar WHERE site_id = :id3) AS ps
            ");
            $b->execute([':id1' => $id, ':id2' => $id, ':id3' => $id]);
            $bag = $b->fetch(PDO::FETCH_ASSOC);
            if ((int)$bag['ie'] > 0 || (int)$bag['ar'] > 0 || (int)$bag['ps'] > 0) {
                json_out(409, ["message" => "Bu tesise bağlı iş emri, arıza veya periyodik şablon kayıtları var. Önce onları silin."]);
            }
            $del = $db->prepare("DELETE FROM siteler WHERE id = :id AND firma_id = :fid");
            $del->execute([':id' => $id, ':fid' => $firma_id]);
            json_out(200, ["message" => "Tesis silindi."]);
        }

        if ($islem === 'qr_yenile') {
            $kod = yeniSiteQr($db);
            $upd = $db->prepare("UPDATE siteler SET qr_kod = :k WHERE id = :id AND firma_id = :fid");
            $upd->execute([':k' => $kod, ':id' => $id, ':fid' => $firma_id]);
            json_out(200, ["message" => "Yeni QR üretildi.", "qr_kod" => $kod]);
        }

        if ($islem === 'guncelle') {
            if (!isset($data->ad) || trim($data->ad) === '') {
                json_out(400, ["message" => "Site adı zorunludur."]);
            }
            $ad     = trim($data->ad);
            $adres  = isset($data->adres) ? trim($data->adres) : null;
            $enlem  = (isset($data->enlem)  && $data->enlem  !== '') ? (float)$data->enlem  : null;
            $boylam = (isset($data->boylam) && $data->boylam !== '') ? (float)$data->boylam : null;

            $upd = $db->prepare("
                UPDATE siteler SET ad = :ad, adres = :adres, enlem = :enlem, boylam = :boylam
                WHERE id = :id AND firma_id = :fid
            ");
            $upd->execute([
                ':ad' => $ad, ':adres' => $adres, ':enlem' => $enlem, ':boylam' => $boylam,
                ':id' => $id, ':fid' => $firma_id,
            ]);
            json_out(200, ["message" => "Tesis güncellendi."]);
        }

        json_out(400, ["message" => "Geçersiz işlem."]);
    }

    // --- Yeni site ekle (otomatik QR ile) ---
    if (!isset($data->ad) || trim($data->ad) === '') {
        json_out(400, ["message" => "Site adı zorunludur."]);
    }

    $ad     = trim($data->ad);
    $adres  = isset($data->adres) ? trim($data->adres) : null;
    // Konum opsiyonel; boş ise NULL kaydedilir (50m kuralı bu sitelerde uygulanmaz)
    $enlem  = (isset($data->enlem)  && $data->enlem  !== '') ? (float)$data->enlem  : null;
    $boylam = (isset($data->boylam) && $data->boylam !== '') ? (float)$data->boylam : null;
    $qr_kod = yeniSiteQr($db);

    $stmt = $db->prepare("
        INSERT INTO siteler (firma_id, ad, adres, enlem, boylam, qr_kod)
        VALUES (:firma_id, :ad, :adres, :enlem, :boylam, :qr_kod)
    ");
    $stmt->execute([
        ':firma_id' => $firma_id,
        ':ad' => $ad,
        ':adres' => $adres,
        ':enlem' => $enlem,
        ':boylam' => $boylam,
        ':qr_kod' => $qr_kod,
    ]);

    json_out(201, ["message" => "Site eklendi.", "id" => (int)$db->lastInsertId(), "qr_kod" => $qr_kod]);
}

json_out(405, ["message" => "Desteklenmeyen metot."]);
