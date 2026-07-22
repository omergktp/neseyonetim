<?php
// backend/api/admin/is_emirleri.php
// GET  -> firmaya ait iş emirlerini listeler (opsiyonel ?durum= filtresi)
// POST -> { ...alanlar }                 : yeni iş emri oluşturur (personele görev atama)
//      -> { id, islem: 'sil' }           : iş emrini siler (alt görev + masraflar cascade)
//      -> { id, islem: 'guncelle', ... } : iş emrini günceller

require_once __DIR__ . '/../../core/bootstrap.php';
cors();

$user = require_admin();
$firma_id = $user->firma_id;
$db = (new Database())->getConnection();

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

// Atanan site ve personelin bu firmaya ait olduğunu doğrular (KURAL 1). Hatada json_out.
function siteVePersonelKontrol($db, $firma_id, $site_id, $personel_id) {
    $kontrol = $db->prepare("
        SELECT
            (SELECT COUNT(*) FROM siteler     WHERE id = :sid AND firma_id = :fid)  AS site_ok,
            (SELECT COUNT(*) FROM personeller WHERE id = :pid AND firma_id = :fid2) AS personel_ok
    ");
    $kontrol->execute([':sid' => $site_id, ':fid' => $firma_id, ':pid' => $personel_id, ':fid2' => $firma_id]);
    $ok = $kontrol->fetch(PDO::FETCH_ASSOC);
    if ((int)$ok['site_ok'] === 0) {
        json_out(422, ["message" => "Seçilen site firmanıza ait değil."]);
    }
    if ((int)$ok['personel_ok'] === 0) {
        json_out(422, ["message" => "Seçilen personel firmanıza ait değil."]);
    }
}

if ($method === 'GET') {
    $durum = $_GET['durum'] ?? null;

    $sql = "
        SELECT
            ie.id, ie.site_id, ie.personel_id, ie.baslik, ie.aciklama, ie.durum, ie.qr_kod,
            ie.planlanan_baslangic_tarihi, ie.tamamlanma_tarihi, ie.olusturma_tarihi,
            s.ad AS site_adi,
            p.ad_soyad AS personel_adi
        FROM is_emirleri ie
        LEFT JOIN siteler s     ON ie.site_id = s.id
        LEFT JOIN personeller p ON ie.personel_id = p.id
        WHERE ie.firma_id = :firma_id
    ";
    $params = [':firma_id' => $firma_id];

    if ($durum !== null && in_array($durum, ['bekliyor', 'devam_ediyor', 'tamamlandi', 'iptal'], true)) {
        $sql .= " AND ie.durum = :durum";
        $params[':durum'] = $durum;
    }
    $sql .= " ORDER BY ie.olusturma_tarihi DESC";

    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    json_out(200, ["data" => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
}

if ($method === 'POST') {
    $data = read_json_body();

    // --- Mevcut iş emri: sil / güncelle ---
    if (isset($data->id, $data->islem)) {
        $id = (int)$data->id;
        $islem = $data->islem;

        if ($islem === 'sil') {
            // alt görevler ve masraflar FK ON DELETE CASCADE ile birlikte silinir.
            $stmt = $db->prepare("DELETE FROM is_emirleri WHERE id = :id AND firma_id = :fid");
            $stmt->execute([':id' => $id, ':fid' => $firma_id]);
            if ($stmt->rowCount() === 0) {
                json_out(404, ["message" => "İş emri bulunamadı."]);
            }
            json_out(200, ["message" => "İş emri silindi."]);
        }

        if ($islem === 'guncelle') {
            $chk = $db->prepare("SELECT id FROM is_emirleri WHERE id = :id AND firma_id = :fid LIMIT 1");
            $chk->execute([':id' => $id, ':fid' => $firma_id]);
            if (!$chk->fetch()) {
                json_out(404, ["message" => "İş emri bulunamadı."]);
            }
            if (!isset($data->site_id, $data->personel_id, $data->baslik) || trim($data->baslik) === '') {
                json_out(400, ["message" => "Eksik bilgi. (site_id, personel_id, baslik gerekli)"]);
            }
            $site_id     = (int)$data->site_id;
            $personel_id = (int)$data->personel_id;
            $baslik      = trim($data->baslik);
            $aciklama    = isset($data->aciklama) ? trim($data->aciklama) : null;
            $qr_kod      = isset($data->qr_kod) && trim($data->qr_kod) !== '' ? trim($data->qr_kod) : null;
            $planlanan   = isset($data->planlanan_baslangic_tarihi) && $data->planlanan_baslangic_tarihi !== ''
                            ? $data->planlanan_baslangic_tarihi : null;

            siteVePersonelKontrol($db, $firma_id, $site_id, $personel_id);

            $upd = $db->prepare("
                UPDATE is_emirleri SET
                    site_id = :s, personel_id = :p, baslik = :b, aciklama = :a,
                    qr_kod = :q, planlanan_baslangic_tarihi = :pl
                WHERE id = :id AND firma_id = :fid
            ");
            $upd->execute([
                ':s' => $site_id, ':p' => $personel_id, ':b' => $baslik, ':a' => $aciklama,
                ':q' => $qr_kod, ':pl' => $planlanan, ':id' => $id, ':fid' => $firma_id,
            ]);
            json_out(200, ["message" => "İş emri güncellendi."]);
        }

        json_out(400, ["message" => "Geçersiz işlem."]);
    }

    // --- Yeni iş emri oluştur ---
    if (!isset($data->site_id, $data->personel_id, $data->baslik) || trim($data->baslik) === '') {
        json_out(400, ["message" => "Eksik bilgi. (site_id, personel_id, baslik gerekli)"]);
    }

    $site_id     = (int)$data->site_id;
    $personel_id = (int)$data->personel_id;
    $baslik      = trim($data->baslik);
    $aciklama    = isset($data->aciklama) ? trim($data->aciklama) : null;
    $qr_kod      = isset($data->qr_kod) && trim($data->qr_kod) !== '' ? trim($data->qr_kod) : null;
    $planlanan   = isset($data->planlanan_baslangic_tarihi) && $data->planlanan_baslangic_tarihi !== ''
                    ? $data->planlanan_baslangic_tarihi : null;

    siteVePersonelKontrol($db, $firma_id, $site_id, $personel_id);

    $stmt = $db->prepare("
        INSERT INTO is_emirleri
            (firma_id, site_id, personel_id, baslik, aciklama, qr_kod, durum, planlanan_baslangic_tarihi)
        VALUES
            (:firma_id, :site_id, :personel_id, :baslik, :aciklama, :qr_kod, 'bekliyor', :planlanan)
    ");
    $stmt->execute([
        ':firma_id' => $firma_id,
        ':site_id' => $site_id,
        ':personel_id' => $personel_id,
        ':baslik' => $baslik,
        ':aciklama' => $aciklama,
        ':qr_kod' => $qr_kod,
        ':planlanan' => $planlanan,
    ]);
    $yeni_id = (int)$db->lastInsertId();

    // Atanan personele anlık bildirim gönder (FCM). Hata olsa bile görev oluşturmayı bozmaz.
    try {
        require_once __DIR__ . '/../../core/FcmSender.php';
        $t = $db->prepare("SELECT fcm_token FROM personeller WHERE id = :pid AND firma_id = :fid");
        $t->execute([':pid' => $personel_id, ':fid' => $firma_id]);
        $fcm = $t->fetchColumn();
        if (!empty($fcm)) {
            FcmSender::send($fcm, 'Yeni Görev Atandı', $baslik, [
                'tip' => 'yeni_gorev',
                'is_emri_id' => (string)$yeni_id,
            ]);
        }
    } catch (Throwable $e) {
        // Sessizce yut; bildirim opsiyoneldir.
    }

    json_out(201, ["message" => "İş emri oluşturuldu ve personele atandı.", "id" => $yeni_id]);
}

json_out(405, ["message" => "Desteklenmeyen metot."]);
