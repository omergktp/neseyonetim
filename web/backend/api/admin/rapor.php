<?php
// backend/api/admin/rapor.php
// GET -> Aylık tesis/faaliyet raporu verisi.
// Parametreler: ?month=YYYY-MM (varsayılan: içinde bulunulan ay), ?site_id=<opsiyonel>

require_once __DIR__ . '/../../core/bootstrap.php';
cors();

$user = require_admin();
$firma_id = $user->firma_id;
$db = (new Database())->getConnection();

// Ay aralığını hesapla
$month = $_GET['month'] ?? date('Y-m');
if (!preg_match('/^\d{4}-\d{2}$/', $month)) {
    json_out(400, ["message" => "Geçersiz ay formatı. (YYYY-MM bekleniyor)"]);
}
$baslangic = $month . '-01 00:00:00';
$bitis = date('Y-m-d 00:00:00', strtotime($baslangic . ' +1 month'));

$site_id = isset($_GET['site_id']) && $_GET['site_id'] !== '' ? (int)$_GET['site_id'] : null;

// Firma adı
$f = $db->prepare("SELECT ad FROM firmalar WHERE id = :id");
$f->execute([':id' => $firma_id]);
$firma_ad = $f->fetchColumn() ?: '';

// Site adı (seçildiyse, ve firmaya ait mi doğrula)
$site_ad = 'Tüm Tesisler';
if ($site_id !== null) {
    $s = $db->prepare("SELECT ad FROM siteler WHERE id = :sid AND firma_id = :fid");
    $s->execute([':sid' => $site_id, ':fid' => $firma_id]);
    $site_ad = $s->fetchColumn();
    if ($site_ad === false) {
        json_out(422, ["message" => "Site firmanıza ait değil."]);
    }
}

// Tamamlanan görev sayısı
$sql_gorev = "SELECT COUNT(*) FROM is_emirleri
              WHERE firma_id = :fid AND durum = 'tamamlandi'
              AND tamamlanma_tarihi >= :bas AND tamamlanma_tarihi < :bit";
$p_gorev = [':fid' => $firma_id, ':bas' => $baslangic, ':bit' => $bitis];
if ($site_id !== null) { $sql_gorev .= " AND site_id = :sid"; $p_gorev[':sid'] = $site_id; }
$g = $db->prepare($sql_gorev);
$g->execute($p_gorev);
$tamamlanan_gorev = (int)$g->fetchColumn();

// Çözülen arıza sayısı
$sql_ariza = "SELECT COUNT(*) FROM arizalar
              WHERE firma_id = :fid AND durum = 'cozuldu'
              AND cozum_tarihi >= :bas AND cozum_tarihi < :bit";
$p_ariza = [':fid' => $firma_id, ':bas' => $baslangic, ':bit' => $bitis];
if ($site_id !== null) { $sql_ariza .= " AND site_id = :sid"; $p_ariza[':sid'] = $site_id; }
$a = $db->prepare($sql_ariza);
$a->execute($p_ariza);
$cozulen_ariza = (int)$a->fetchColumn();

// Masraf listesi (ilgili ay) — iş emri veya arıza üzerinden siteye bağlanır
$sql_masraf = "
    SELECT
        mt.id, mt.kalem_adi, mt.tutar, mt.durum, mt.olusturma_tarihi,
        p.ad_soyad AS personel_adi, p.rol AS personel_rol
    FROM malzeme_talepleri mt
    LEFT JOIN personeller p ON mt.personel_id = p.id
    LEFT JOIN is_emirleri ie ON mt.is_emri_id = ie.id
    LEFT JOIN arizalar ar    ON mt.ariza_id = ar.id
    WHERE mt.firma_id = :fid
      AND mt.olusturma_tarihi >= :bas AND mt.olusturma_tarihi < :bit
";
$p_masraf = [':fid' => $firma_id, ':bas' => $baslangic, ':bit' => $bitis];
if ($site_id !== null) {
    $sql_masraf .= " AND (ie.site_id = :sid OR ar.site_id = :sid2)";
    $p_masraf[':sid'] = $site_id;
    $p_masraf[':sid2'] = $site_id;
}
$sql_masraf .= " ORDER BY mt.olusturma_tarihi ASC";
$m = $db->prepare($sql_masraf);
$m->execute($p_masraf);
$masraflar = $m->fetchAll(PDO::FETCH_ASSOC);

$toplam_masraf = 0.0;
foreach ($masraflar as $row) {
    $toplam_masraf += (float)$row['tutar'];
}

json_out(200, [
    "firma_ad"  => $firma_ad,
    "site_ad"   => $site_ad,
    "donem"     => $month,
    "istatistik" => [
        "tamamlanan_gorev" => $tamamlanan_gorev,
        "cozulen_ariza"    => $cozulen_ariza,
        "toplam_masraf"    => round($toplam_masraf, 2),
    ],
    "masraflar" => $masraflar,
]);
