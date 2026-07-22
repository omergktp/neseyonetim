<?php
// backend/api/admin/dashboard.php
// Yönetici paneli özeti. Opsiyonel ?site_id= ile tek tesise odaklanır.
// Ayrıca her tesisin özetini (site_ozet) döndürür — çok tesisli firmalar için.

require_once __DIR__ . '/../../core/bootstrap.php';
cors();

$user = require_admin();
$firma_id = $user->firma_id;
$db = (new Database())->getConnection();

$site_id = isset($_GET['site_id']) && $_GET['site_id'] !== '' ? (int)$_GET['site_id'] : null;

// Seçili tesis firmaya ait mi?
if ($site_id !== null) {
    $s = $db->prepare("SELECT id FROM siteler WHERE id = :sid AND firma_id = :fid");
    $s->execute([':sid' => $site_id, ':fid' => $firma_id]);
    if (!$s->fetch()) {
        json_out(422, ["message" => "Tesis firmanıza ait değil."]);
    }
}

// Bu ayın başı (tamamlanan iş istatistiği için)
$ay_bas = date('Y-m-01 00:00:00');

// İş emri durum sayıları (opsiyonel tesis filtresi)
$is_sql = "SELECT
        SUM(durum = 'tamamlandi')   AS tamamlanan,
        SUM(durum = 'devam_ediyor') AS devam_eden,
        SUM(durum = 'bekliyor')     AS bekleyen
    FROM is_emirleri WHERE firma_id = :firma_id";
$is_params = [':firma_id' => $firma_id];
if ($site_id !== null) { $is_sql .= " AND site_id = :sid"; $is_params[':sid'] = $site_id; }
$is_stat = $db->prepare($is_sql);
$is_stat->execute($is_params);
$is = $is_stat->fetch(PDO::FETCH_ASSOC);

// Açık arıza sayısı (açık + bekliyor + dış destek)
$ariza_sql = "SELECT COUNT(*) AS acik_ariza FROM arizalar
              WHERE firma_id = :firma_id AND durum IN ('acik', 'bekliyor', 'dis_destek')";
$ariza_params = [':firma_id' => $firma_id];
if ($site_id !== null) { $ariza_sql .= " AND site_id = :sid"; $ariza_params[':sid'] = $site_id; }
$ariza_stat = $db->prepare($ariza_sql);
$ariza_stat->execute($ariza_params);
$acik_ariza = (int)$ariza_stat->fetch(PDO::FETCH_ASSOC)['acik_ariza'];

// Aktif personel (firma geneli — personel tesise bağlı değil)
$personel_stat = $db->prepare("SELECT COUNT(*) AS aktif_personel FROM personeller WHERE firma_id = :firma_id AND aktif = 1");
$personel_stat->execute([':firma_id' => $firma_id]);
$aktif_personel = (int)$personel_stat->fetch(PDO::FETCH_ASSOC)['aktif_personel'];

// Son 10 iş emri (opsiyonel tesis filtresi)
$son_sql = "
    SELECT ie.id, ie.baslik, ie.durum, ie.olusturma_tarihi,
           s.ad AS site_adi, p.ad_soyad AS personel_adi
    FROM is_emirleri ie
    LEFT JOIN siteler s     ON ie.site_id = s.id
    LEFT JOIN personeller p ON ie.personel_id = p.id
    WHERE ie.firma_id = :firma_id";
$son_params = [':firma_id' => $firma_id];
if ($site_id !== null) { $son_sql .= " AND ie.site_id = :sid"; $son_params[':sid'] = $site_id; }
$son_sql .= " ORDER BY ie.olusturma_tarihi DESC LIMIT 10";
$son_isler = $db->prepare($son_sql);
$son_isler->execute($son_params);
$liste = $son_isler->fetchAll(PDO::FETCH_ASSOC);

// Tesis bazlı özet — her tesis için devam eden iş / açık arıza / bu ay tamamlanan
$ozet = $db->prepare("
    SELECT s.id, s.ad,
        (SELECT COUNT(*) FROM is_emirleri ie WHERE ie.site_id = s.id AND ie.durum = 'devam_ediyor') AS devam_eden,
        (SELECT COUNT(*) FROM arizalar a WHERE a.site_id = s.id AND a.durum IN ('acik','bekliyor','dis_destek')) AS acik_ariza,
        (SELECT COUNT(*) FROM is_emirleri ie WHERE ie.site_id = s.id AND ie.durum = 'tamamlandi' AND ie.tamamlanma_tarihi >= :ay_bas) AS bu_ay_tamamlanan
    FROM siteler s
    WHERE s.firma_id = :firma_id AND s.aktif = 1
    ORDER BY s.ad ASC
");
$ozet->execute([':firma_id' => $firma_id, ':ay_bas' => $ay_bas]);
$site_ozet = $ozet->fetchAll(PDO::FETCH_ASSOC);

json_out(200, [
    "istatistik" => [
        "tamamlanan_is"   => (int)($is['tamamlanan'] ?? 0),
        "devam_eden_is"   => (int)($is['devam_eden'] ?? 0),
        "bekleyen_is"     => (int)($is['bekleyen'] ?? 0),
        "acik_ariza"      => $acik_ariza,
        "aktif_personel"  => $aktif_personel,
    ],
    "secili_site_id"  => $site_id,
    "site_ozet"       => $site_ozet,
    "son_is_emirleri" => $liste,
]);
