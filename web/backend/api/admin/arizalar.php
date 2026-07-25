<?php
// backend/api/admin/arizalar.php
// GET -> firmaya ait arıza kayıtlarını listeler (opsiyonel ?durum= filtresi)

require_once __DIR__ . '/../../core/bootstrap.php';
cors();

$user = require_admin();
$firma_id = $user->firma_id;
$db = (new Database())->getConnection();

$durum = $_GET['durum'] ?? null;

$sql = "
    SELECT
        a.id, a.baslik, a.aciklama, a.teknik_notu, a.durum, a.oncelik, a.fotograf_url, a.cozum_fotograf_url,
        a.olusturma_tarihi, a.cozum_tarihi,
        a.site_id, a.teknik_personel_id,
        s.ad AS site_adi,
        b.ad_soyad AS bildiren_adi,
        t.ad_soyad AS teknik_adi
    FROM arizalar a
    LEFT JOIN siteler s     ON a.site_id = s.id
    LEFT JOIN personeller b ON a.bildiren_personel_id = b.id
    LEFT JOIN personeller t ON a.teknik_personel_id = t.id
    WHERE a.firma_id = :firma_id
";
$params = [':firma_id' => $firma_id];

if ($durum !== null && in_array($durum, ['acik', 'bekliyor', 'cozuldu', 'iptal', 'dis_destek'], true)) {
    $sql .= " AND a.durum = :durum";
    $params[':durum'] = $durum;
}
$sql .= " ORDER BY a.olusturma_tarihi DESC";

$stmt = $db->prepare($sql);
$stmt->execute($params);
json_out(200, ["data" => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
