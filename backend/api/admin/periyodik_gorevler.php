<?php
// backend/api/admin/periyodik_gorevler.php
// GET  -> firmaya ait periyodik görev şablonlarını listeler
// POST -> { ...alanlar } (id yoksa)        : yeni şablon oluşturur
//      -> { id, islem: 'sil' }             : şablonu siler
//      -> { id, islem: 'aktif_degistir' }  : aktiflik durumunu değiştirir
//      -> { id, islem: 'uret' }            : şablondan HEMEN iş emri üretir (geceyi beklemeden)
//      -> { id, islem: 'guncelle', ... }   : şablonu günceller

require_once __DIR__ . '/../../core/bootstrap.php';
cors();

$user = require_admin();
$firma_id = $user->firma_id;
$db = (new Database())->getConnection();

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

// Şablon girdilerini doğrular ve normalize eder (oluştur + güncelle ortak kullanır).
// Hata olursa json_out ile yanıt verip çıkar.
function sablonGirdisiAl($data, $db, $firma_id) {
    if (!isset($data->site_id, $data->personel_id, $data->baslik, $data->tekrar_tipi) || trim($data->baslik) === '') {
        json_out(400, ["message" => "Eksik bilgi. (site_id, personel_id, baslik, tekrar_tipi gerekli)"]);
    }

    $site_id      = (int)$data->site_id;
    $personel_id  = (int)$data->personel_id;
    $baslik       = trim($data->baslik);
    $aciklama     = isset($data->aciklama) ? trim($data->aciklama) : null;
    $alt_gorevler = isset($data->alt_gorevler) && trim($data->alt_gorevler) !== '' ? trim($data->alt_gorevler) : null;
    $tekrar_tipi  = $data->tekrar_tipi;

    if (!in_array($tekrar_tipi, ['gunluk', 'haftalik', 'aylik'], true)) {
        json_out(422, ["message" => "Geçersiz tekrar tipi."]);
    }

    $tekrar_gunu = null;
    if ($tekrar_tipi === 'haftalik') {
        $tekrar_gunu = isset($data->tekrar_gunu) ? (int)$data->tekrar_gunu : 0;
        if ($tekrar_gunu < 1 || $tekrar_gunu > 7) {
            json_out(422, ["message" => "Haftalık tekrar için gün 1-7 (Pazartesi-Pazar) olmalı."]);
        }
    } elseif ($tekrar_tipi === 'aylik') {
        $tekrar_gunu = isset($data->tekrar_gunu) ? (int)$data->tekrar_gunu : 0;
        if ($tekrar_gunu < 1 || $tekrar_gunu > 31) {
            json_out(422, ["message" => "Aylık tekrar için ayın günü 1-31 olmalı."]);
        }
    }

    // KURAL 1: site ve personel gerçekten bu firmaya mı ait?
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

    return compact('site_id', 'personel_id', 'baslik', 'aciklama', 'alt_gorevler', 'tekrar_tipi', 'tekrar_gunu');
}

if ($method === 'GET') {
    $sql = "
        SELECT
            ps.id, ps.site_id, ps.personel_id, ps.baslik, ps.aciklama, ps.alt_gorevler,
            ps.tekrar_tipi, ps.tekrar_gunu, ps.son_uretim_tarihi, ps.aktif, ps.olusturma_tarihi,
            s.ad AS site_adi,
            p.ad_soyad AS personel_adi
        FROM periyodik_sablonlar ps
        LEFT JOIN siteler s     ON ps.site_id = s.id
        LEFT JOIN personeller p ON ps.personel_id = p.id
        WHERE ps.firma_id = :firma_id
        ORDER BY ps.aktif DESC, ps.olusturma_tarihi DESC
    ";
    $stmt = $db->prepare($sql);
    $stmt->execute([':firma_id' => $firma_id]);
    json_out(200, ["data" => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
}

if ($method === 'POST') {
    $data = read_json_body();

    // --- Mevcut şablon üzerinde işlem ---
    if (isset($data->id, $data->islem)) {
        $id = (int)$data->id;
        $islem = $data->islem;

        if ($islem === 'sil') {
            // Bu şablondan üretilmiş, henüz BAŞLANMAMIŞ (bekliyor) iş emirlerini de kaldır;
            // böylece şablon silinince personelin listesinden de düşer.
            // Başlanmış/tamamlanmış olanlar (devam_ediyor/tamamlandi) geçmiş olarak korunur.
            $delIe = $db->prepare("DELETE FROM is_emirleri
                                   WHERE sablon_id = :sid AND firma_id = :fid AND durum = 'bekliyor'");
            $delIe->execute([':sid' => $id, ':fid' => $firma_id]);
            $silinenGorev = $delIe->rowCount();

            $stmt = $db->prepare("DELETE FROM periyodik_sablonlar WHERE id = :id AND firma_id = :fid");
            $stmt->execute([':id' => $id, ':fid' => $firma_id]);
            if ($stmt->rowCount() === 0) {
                json_out(404, ["message" => "Şablon bulunamadı."]);
            }
            $msg = "Şablon silindi.";
            if ($silinenGorev > 0) {
                $msg .= " Personelin bekleyen $silinenGorev görevi de kaldırıldı.";
            }
            json_out(200, ["message" => $msg]);
        }

        if ($islem === 'aktif_degistir') {
            $stmt = $db->prepare("UPDATE periyodik_sablonlar SET aktif = 1 - aktif WHERE id = :id AND firma_id = :fid");
            $stmt->execute([':id' => $id, ':fid' => $firma_id]);
            if ($stmt->rowCount() === 0) {
                json_out(404, ["message" => "Şablon bulunamadı veya durum zaten aynı."]);
            }
            json_out(200, ["message" => "Şablon durumu güncellendi."]);
        }

        // Şablondan HEMEN iş emri üret (geceyi beklemeden).
        if ($islem === 'uret') {
            require_once __DIR__ . '/../../core/PeriodicGenerator.php';
            $sel = $db->prepare("SELECT * FROM periyodik_sablonlar WHERE id = :id AND firma_id = :fid LIMIT 1");
            $sel->execute([':id' => $id, ':fid' => $firma_id]);
            $s = $sel->fetch(PDO::FETCH_ASSOC);
            if (!$s) {
                json_out(404, ["message" => "Şablon bulunamadı."]);
            }
            $yeni = PeriodicGenerator::uret($db, $s, date('Y-m-d'));
            if ($yeni === null) {
                json_out(422, ["message" => "İş emri üretilemedi: atanan site veya personel pasif/silinmiş."]);
            }
            if ($yeni === 0) {
                json_out(409, ["message" => "Bu şablondan bugün zaten iş emri üretilmiş. Aynı gün tekrar üretilmez."]);
            }
            json_out(201, ["message" => "İş emri oluşturuldu ve personele atandı.", "is_emri_id" => $yeni]);
        }

        // Şablonu güncelle.
        if ($islem === 'guncelle') {
            $chk = $db->prepare("SELECT id FROM periyodik_sablonlar WHERE id = :id AND firma_id = :fid LIMIT 1");
            $chk->execute([':id' => $id, ':fid' => $firma_id]);
            if (!$chk->fetch()) {
                json_out(404, ["message" => "Şablon bulunamadı."]);
            }
            $g = sablonGirdisiAl($data, $db, $firma_id);
            $upd = $db->prepare("
                UPDATE periyodik_sablonlar SET
                    site_id = :s, personel_id = :p, baslik = :b, aciklama = :a,
                    alt_gorevler = :ag, tekrar_tipi = :tt, tekrar_gunu = :tg
                WHERE id = :id AND firma_id = :fid
            ");
            $upd->execute([
                ':s' => $g['site_id'], ':p' => $g['personel_id'], ':b' => $g['baslik'], ':a' => $g['aciklama'],
                ':ag' => $g['alt_gorevler'], ':tt' => $g['tekrar_tipi'], ':tg' => $g['tekrar_gunu'],
                ':id' => $id, ':fid' => $firma_id,
            ]);
            json_out(200, ["message" => "Şablon güncellendi."]);
        }

        json_out(400, ["message" => "Geçersiz işlem."]);
    }

    // --- Yeni şablon oluştur ---
    $g = sablonGirdisiAl($data, $db, $firma_id);
    $stmt = $db->prepare("
        INSERT INTO periyodik_sablonlar
            (firma_id, site_id, personel_id, baslik, aciklama, alt_gorevler, tekrar_tipi, tekrar_gunu, aktif)
        VALUES
            (:firma_id, :site_id, :personel_id, :baslik, :aciklama, :alt_gorevler, :tekrar_tipi, :tekrar_gunu, 1)
    ");
    $stmt->execute([
        ':firma_id'     => $firma_id,
        ':site_id'      => $g['site_id'],
        ':personel_id'  => $g['personel_id'],
        ':baslik'       => $g['baslik'],
        ':aciklama'     => $g['aciklama'],
        ':alt_gorevler' => $g['alt_gorevler'],
        ':tekrar_tipi'  => $g['tekrar_tipi'],
        ':tekrar_gunu'  => $g['tekrar_gunu'],
    ]);

    json_out(201, ["message" => "Periyodik görev şablonu oluşturuldu.", "id" => (int)$db->lastInsertId()]);
}

json_out(405, ["message" => "Desteklenmeyen metot."]);
