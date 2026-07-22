<?php
// backend/api/admin/personeller.php
// GET  -> firmaya ait personelleri listeler
// POST -> { ...alanlar }                 : yeni personel ekler
//      -> { id, islem: 'guncelle', ... } : personeli günceller (şifre opsiyonel)
//      -> { id, islem: 'aktif_degistir' }: aktif/pasif durumunu değiştirir
//      -> { id, islem: 'sil' }           : personeli siler (bağlı kayıt yoksa)

require_once __DIR__ . '/../../core/bootstrap.php';
cors();

$user = require_admin();
$firma_id = $user->firma_id;
$kendi_id = (int)($user->personel_id ?? 0); // giriş yapan yönetici (kendini silmeyi engelle)
$db = (new Database())->getConnection();

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    $stmt = $db->prepare("
        SELECT id, ad_soyad, telefon, rol, aktif, olusturma_tarihi
        FROM personeller
        WHERE firma_id = :firma_id
        ORDER BY ad_soyad ASC
    ");
    $stmt->bindParam(':firma_id', $firma_id);
    $stmt->execute();
    json_out(200, ["data" => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
}

if ($method === 'POST') {
    $data = read_json_body();

    // --- Mevcut personel üzerinde işlem ---
    if (isset($data->id, $data->islem)) {
        $id = (int)$data->id;
        $islem = $data->islem;

        // Personel bu firmaya ait mi?
        $chk = $db->prepare("SELECT id FROM personeller WHERE id = :id AND firma_id = :fid LIMIT 1");
        $chk->execute([':id' => $id, ':fid' => $firma_id]);
        if (!$chk->fetch()) {
            json_out(404, ["message" => "Personel bulunamadı."]);
        }

        if ($islem === 'aktif_degistir') {
            if ($id === $kendi_id) {
                json_out(409, ["message" => "Kendi hesabınızı pasifleştiremezsiniz."]);
            }
            $upd = $db->prepare("UPDATE personeller SET aktif = 1 - aktif WHERE id = :id AND firma_id = :fid");
            $upd->execute([':id' => $id, ':fid' => $firma_id]);
            log_action($db, $user, 'personel_aktif_degistir', 'personel', $id);
            json_out(200, ["message" => "Personel durumu güncellendi."]);
        }

        if ($islem === 'sil') {
            if ($id === $kendi_id) {
                json_out(409, ["message" => "Kendi hesabınızı silemezsiniz."]);
            }
            // Bağlı kayıt varsa silme (geçmişi cascade ile yok etmeyi önle); pasife alınması önerilir.
            $b = $db->prepare("
                SELECT
                    (SELECT COUNT(*) FROM is_emirleri      WHERE personel_id = :id1) AS ie,
                    (SELECT COUNT(*) FROM arizalar          WHERE bildiren_personel_id = :id2 OR teknik_personel_id = :id3) AS ar,
                    (SELECT COUNT(*) FROM malzeme_talepleri WHERE personel_id = :id4) AS mt
            ");
            $b->execute([':id1' => $id, ':id2' => $id, ':id3' => $id, ':id4' => $id]);
            $bag = $b->fetch(PDO::FETCH_ASSOC);
            if ((int)$bag['ie'] > 0 || (int)$bag['ar'] > 0 || (int)$bag['mt'] > 0) {
                json_out(409, ["message" => "Bu personele bağlı iş emri/arıza/masraf kayıtları var. Silmek yerine 'Pasif' yapabilirsiniz."]);
            }
            $del = $db->prepare("DELETE FROM personeller WHERE id = :id AND firma_id = :fid");
            $del->execute([':id' => $id, ':fid' => $firma_id]);
            log_action($db, $user, 'personel_sil', 'personel', $id);
            json_out(200, ["message" => "Personel silindi."]);
        }

        if ($islem === 'guncelle') {
            if (!isset($data->ad_soyad, $data->telefon, $data->rol) || trim($data->ad_soyad) === '' || trim($data->telefon) === '') {
                json_out(400, ["message" => "Eksik bilgi. (ad_soyad, telefon, rol gerekli)"]);
            }
            $rol = $data->rol;
            if (!in_array($rol, ['yonetici', 'temizlik', 'teknik'], true)) {
                json_out(400, ["message" => "Geçersiz rol."]);
            }
            $ad_soyad = trim($data->ad_soyad);
            $telefon  = trim($data->telefon);
            // Şifre: doluysa güncelle, boşsa dokunma.
            $sifreVar = isset($data->sifre) && trim((string)$data->sifre) !== '';

            try {
                if ($sifreVar) {
                    $hash = password_hash((string)$data->sifre, PASSWORD_DEFAULT);
                    $upd = $db->prepare("UPDATE personeller SET ad_soyad = :a, telefon = :t, rol = :r, sifre = :s
                                         WHERE id = :id AND firma_id = :fid");
                    $upd->execute([':a' => $ad_soyad, ':t' => $telefon, ':r' => $rol, ':s' => $hash, ':id' => $id, ':fid' => $firma_id]);
                } else {
                    $upd = $db->prepare("UPDATE personeller SET ad_soyad = :a, telefon = :t, rol = :r
                                         WHERE id = :id AND firma_id = :fid");
                    $upd->execute([':a' => $ad_soyad, ':t' => $telefon, ':r' => $rol, ':id' => $id, ':fid' => $firma_id]);
                }
                log_action($db, $user, 'personel_guncelle', 'personel', $id, $sifreVar ? 'şifre de değiştirildi' : null);
                json_out(200, ["message" => "Personel güncellendi."]);
            } catch (PDOException $e) {
                if ($e->getCode() === '23000') {
                    json_out(409, ["message" => "Bu telefon numarası firmanızda zaten kayıtlı."]);
                }
                json_out(500, ["message" => "Personel güncellenemedi."]);
            }
        }

        json_out(400, ["message" => "Geçersiz işlem."]);
    }

    // --- Yeni personel ekle ---
    if (!isset($data->ad_soyad, $data->telefon, $data->sifre, $data->rol)) {
        json_out(400, ["message" => "Eksik bilgi. (ad_soyad, telefon, sifre, rol gerekli)"]);
    }

    $rol = $data->rol;
    if (!in_array($rol, ['yonetici', 'temizlik', 'teknik'], true)) {
        json_out(400, ["message" => "Geçersiz rol. (yonetici, temizlik veya teknik)"]);
    }

    $ad_soyad = trim($data->ad_soyad);
    $telefon  = trim($data->telefon);
    // Şifre güvenli şekilde hash'lenerek saklanır (bcrypt)
    $sifre    = password_hash((string)$data->sifre, PASSWORD_DEFAULT);

    try {
        $stmt = $db->prepare("
            INSERT INTO personeller (firma_id, ad_soyad, telefon, sifre, rol)
            VALUES (:firma_id, :ad_soyad, :telefon, :sifre, :rol)
        ");
        $stmt->bindParam(':firma_id', $firma_id);
        $stmt->bindParam(':ad_soyad', $ad_soyad);
        $stmt->bindParam(':telefon', $telefon);
        $stmt->bindParam(':sifre', $sifre);
        $stmt->bindParam(':rol', $rol);
        $stmt->execute();

        $yeniId = (int)$db->lastInsertId();
        log_action($db, $user, 'personel_ekle', 'personel', $yeniId, "rol: $rol");
        json_out(201, ["message" => "Personel eklendi.", "id" => $yeniId]);
    } catch (PDOException $e) {
        // UNIQUE (firma_id, telefon) ihlali
        if ($e->getCode() === '23000') {
            json_out(409, ["message" => "Bu telefon numarası firmanızda zaten kayıtlı."]);
        }
        json_out(500, ["message" => "Personel eklenemedi."]);
    }
}

json_out(405, ["message" => "Desteklenmeyen metot."]);
