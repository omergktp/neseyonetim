<?php
// backend/api/admin/is_emri_detay.php
// GET ?id= -> Tek bir iş emrinin tüm detayı: site/personel, tamamlanma konumu/fotoğrafı, checklist, masraflar.

require_once __DIR__ . '/../../core/bootstrap.php';
cors();

$user = require_admin();
$firma_id = $user->firma_id;
$db = (new Database())->getConnection();

$id = isset($_GET['id']) ? (int)$_GET['id'] : 0;
if ($id <= 0) {
    json_out(400, ["message" => "Geçersiz iş emri id."]);
}

// Ana kayıt (KURAL 1: firma_id şartı)
$stmt = $db->prepare("
    SELECT
        ie.id, ie.baslik, ie.aciklama, ie.durum, ie.qr_kod,
        ie.planlanan_baslangic_tarihi, ie.tamamlanma_tarihi, ie.olusturma_tarihi,
        ie.tamamlanma_enlem, ie.tamamlanma_boylam, ie.kapanis_fotograf_url,
        s.ad AS site_adi, s.adres AS site_adresi, s.enlem AS site_enlem, s.boylam AS site_boylam,
        p.ad_soyad AS personel_adi, p.telefon AS personel_telefon, p.rol AS personel_rol
    FROM is_emirleri ie
    LEFT JOIN siteler s     ON ie.site_id = s.id
    LEFT JOIN personeller p ON ie.personel_id = p.id
    WHERE ie.id = :id AND ie.firma_id = :firma_id
    LIMIT 1
");
$stmt->execute([':id' => $id, ':firma_id' => $firma_id]);
$gorev = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$gorev) {
    json_out(404, ["message" => "İş emri bulunamadı."]);
}

// Checklist (alt görevler)
$alt = $db->prepare("SELECT id, gorev_metni, yapildi_mi FROM is_emirleri_alt_gorevler
                     WHERE is_emri_id = :id AND firma_id = :firma_id");
$alt->execute([':id' => $id, ':firma_id' => $firma_id]);
$gorev['alt_gorevler'] = $alt->fetchAll(PDO::FETCH_ASSOC);

// Bu iş emrine bağlı masraflar
$mas = $db->prepare("
    SELECT mt.id, mt.kalem_adi, mt.tutar, mt.durum, mt.fis_fatura_fotograf, mt.olusturma_tarihi,
           p.ad_soyad AS personel_adi
    FROM malzeme_talepleri mt
    LEFT JOIN personeller p ON mt.personel_id = p.id
    WHERE mt.is_emri_id = :id AND mt.firma_id = :firma_id
    ORDER BY mt.olusturma_tarihi ASC
");
$mas->execute([':id' => $id, ':firma_id' => $firma_id]);
$gorev['masraflar'] = $mas->fetchAll(PDO::FETCH_ASSOC);

json_out(200, ["data" => $gorev]);
