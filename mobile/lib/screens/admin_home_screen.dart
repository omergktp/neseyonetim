import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/fcm_service.dart';
import '../theme/app_theme.dart';
import '../utils/ui_utils.dart';
import 'login_screen.dart';

/// Yönetici mobil görünümü: telefondan firma özeti, masraf onayı ve arıza takibi.
/// Tam yönetim web panelindedir; burası "cepten kontrol" içindir.
class AdminHomeScreen extends StatefulWidget {
  final String themeColor;
  const AdminHomeScreen({super.key, required this.themeColor});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  Map<String, dynamic>? _ozet;      // dashboard.php yanıtı
  List<dynamic> _masraflar = [];    // onay bekleyenler
  List<dynamic> _arizalar = [];
  bool _loading = true;
  String? _hata;

  Color get _primary => AppTheme.parseHex(widget.themeColor);

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() {
      _loading = true;
      _hata = null;
    });
    final sonuclar = await Future.wait([
      ApiService.getAdminDashboard(),
      ApiService.getAdminMasraflar(durum: 'bekliyor'),
      ApiService.getAdminArizalar(),
    ]);
    if (!mounted) return;
    setState(() {
      _ozet = sonuclar[0] as Map<String, dynamic>?;
      final m = sonuclar[1] as List<dynamic>?;
      final a = sonuclar[2] as List<dynamic>?;
      if (m != null) _masraflar = m;
      if (a != null) _arizalar = a;
      _loading = false;
      if (_ozet == null) _hata = 'Veriler yüklenemedi. Bağlantıyı kontrol edin.';
    });
  }

  void _logout() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Yönetici oturumundan çıkmak istiyor musun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Çıkış Yap', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (onay != true) return;
    await FcmService.clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen()));
  }

  Future<void> _masrafKarar(Map m, String islem) async {
    final id = int.tryParse(m['id'].toString()) ?? 0;
    final etiket = islem == 'onayla' ? 'onaylansın' : 'reddedilsin';
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(islem == 'onayla' ? 'Masrafı Onayla' : 'Masrafı Reddet'),
        content: Text('"${m['kalem_adi']}" (${m['tutar']} TL) $etiket mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: islem == 'onayla' ? AppTheme.success : AppTheme.danger,
                foregroundColor: Colors.white),
            child: Text(islem == 'onayla' ? 'Onayla' : 'Reddet'),
          ),
        ],
      ),
    );
    if (onay != true) return;

    final res = await ApiService.adminMasrafIslem(id, islem);
    if (!mounted) return;
    UiUtils.showSnackBar(res['message'], isError: !res['success']);
    if (res['success']) _yukle();
  }

  void _fotoGoster(String? relativePath, String baslik) {
    if (relativePath == null || relativePath.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(baslik, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            InteractiveViewer(
              child: Image.network(
                ApiService.fileUrl(relativePath),
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Padding(
                  padding: EdgeInsets.all(30),
                  child: Text('Fotoğraf yüklenemedi', style: TextStyle(color: AppTheme.textMuted)),
                ),
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Yönetici Paneli', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: _primary,
          flexibleSpace: AppTheme.appBarFlex(_primary),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Yenile', onPressed: _yukle),
            IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
          ],
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              const Tab(icon: Icon(Icons.dashboard_outlined), text: 'Özet'),
              Tab(
                icon: Badge(
                  isLabelVisible: _masraflar.isNotEmpty,
                  label: Text('${_masraflar.length}'),
                  child: const Icon(Icons.receipt_long_outlined),
                ),
                text: 'Onaylar',
              ),
              const Tab(icon: Icon(Icons.handyman_outlined), text: 'Arızalar'),
            ],
          ),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: _primary))
            : TabBarView(
                children: [_ozetSekmesi(), _onaySekmesi(), _arizaSekmesi()],
              ),
      ),
    );
  }

  // ---- ÖZET ----
  Widget _ozetSekmesi() {
    if (_ozet == null) {
      return AppTheme.emptyState(
        icon: Icons.wifi_off_outlined,
        title: 'Özet yüklenemedi',
        subtitle: '${_hata ?? ''}\nAşağı çekerek tekrar deneyebilirsin.',
        accent: AppTheme.danger,
      );
    }
    final s = (_ozet!['istatistik'] as Map?) ?? {};
    final siteler = (_ozet!['site_ozet'] as List?) ?? [];
    final geciken = int.tryParse(s['geciken_is']?.toString() ?? '0') ?? 0;
    final ort = s['ort_cozum_saat'];

    return RefreshIndicator(
      onRefresh: _yukle,
      color: _primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.9,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _statKart('Bekleyen İş', s['bekleyen_is'], Icons.schedule, _primary),
              _statKart('Devam Eden', s['devam_eden_is'], Icons.play_circle_outline, AppTheme.warning),
              _statKart('Geciken İş', s['geciken_is'], Icons.hourglass_bottom,
                  geciken > 0 ? AppTheme.danger : AppTheme.success,
                  vurgula: geciken > 0),
              _statKart('Açık Arıza', s['acik_ariza'], Icons.report_problem_outlined, AppTheme.danger),
              _statKart('Aktif Personel', s['aktif_personel'], Icons.people_outline, AppTheme.info),
              _statKart('Ort. Çözüm', ort != null ? '$ort sa' : '—', Icons.timer_outlined, AppTheme.info),
            ],
          ),
          const SizedBox(height: 20),
          AppTheme.sectionLabel('Tesis Özeti', icon: Icons.location_city_outlined),
          const SizedBox(height: 10),
          ...siteler.map((site) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.cardDecoration,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(site['ad'] ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                    ),
                    _miniRozet('${site['devam_eden']}', 'devam', AppTheme.warning),
                    const SizedBox(width: 6),
                    _miniRozet('${site['acik_ariza']}', 'arıza', AppTheme.danger),
                    const SizedBox(width: 6),
                    _miniRozet('${site['bu_ay_tamamlanan']}', 'bu ay', AppTheme.success),
                  ],
                ),
              )),
          if (siteler.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Henüz tesis eklenmemiş.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted)),
            ),
        ],
      ),
    );
  }

  Widget _statKart(String etiket, dynamic deger, IconData ikon, Color renk, {bool vurgula = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppTheme.cardDecoration.copyWith(
        border: vurgula ? Border.all(color: renk.withValues(alpha: 0.5), width: 1.5) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: renk.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(ikon, color: renk, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${deger ?? '-'}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: vurgula ? renk : AppTheme.textDark)),
                Text(etiket,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniRozet(String deger, String etiket, Color renk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: renk.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
      child: Text('$deger $etiket', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: renk)),
    );
  }

  // ---- ONAY BEKLEYEN MASRAFLAR ----
  Widget _onaySekmesi() {
    return RefreshIndicator(
      onRefresh: _yukle,
      color: _primary,
      child: _masraflar.isEmpty
          ? AppTheme.emptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Onay bekleyen masraf yok',
              subtitle: 'Personel fişli masraf girdikçe burada onayına düşer.',
              accent: _primary,
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _masraflar.length,
              itemBuilder: (context, i) {
                final m = _masraflar[i];
                final ilgili = m['is_emri_baslik'] ?? m['ariza_baslik'] ?? '-';
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(m['kalem_adi'] ?? '-',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark)),
                          ),
                          Text('${m['tutar']} TL',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _primary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${m['personel_adi'] ?? '-'} · $ilgili',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (m['fis_fatura_fotograf'] != null && '${m['fis_fatura_fotograf']}'.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _fotoGoster(m['fis_fatura_fotograf'], 'Fiş / Fatura'),
                              icon: const Icon(Icons.image_outlined, size: 18),
                              label: const Text('Fiş'),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 42),
                                  padding: const EdgeInsets.symmetric(horizontal: 14)),
                            ),
                          const Spacer(),
                          OutlinedButton(
                            onPressed: () => _masrafKarar(m, 'reddet'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.danger,
                                side: const BorderSide(color: AppTheme.danger),
                                minimumSize: const Size(0, 42),
                                padding: const EdgeInsets.symmetric(horizontal: 16)),
                            child: const Text('Reddet'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _masrafKarar(m, 'onayla'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.success,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 42),
                                padding: const EdgeInsets.symmetric(horizontal: 18)),
                            child: const Text('Onayla'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  // ---- ARIZALAR ----
  Widget _arizaSekmesi() {
    return RefreshIndicator(
      onRefresh: _yukle,
      color: _primary,
      child: _arizalar.isEmpty
          ? AppTheme.emptyState(
              icon: Icons.handyman_outlined,
              title: 'Arıza kaydı yok',
              subtitle: 'Sahadan bildirim geldikçe burada listelenir.',
              accent: _primary,
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _arizalar.length,
              itemBuilder: (context, i) {
                final a = _arizalar[i];
                final acil = a['oncelik'] == 'yuksek';
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: AppTheme.cardDecoration,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _arizaDetayGoster(a),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Icon(acil ? Icons.bolt : Icons.warning_amber_rounded,
                                  color: AppTheme.danger, size: 21),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(a['baslik'] ?? '-',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                                      ),
                                      if (acil) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: AppTheme.danger.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8)),
                                          child: const Text('ACİL',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppTheme.danger)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text('${a['site_adi'] ?? '-'} · ${a['teknik_adi'] ?? 'Atanmadı'}',
                                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                                ],
                              ),
                            ),
                            StatusUi.chip(a['durum']),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _arizaDetayGoster(Map a) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a['baslik'] ?? 'Arıza'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                StatusUi.chip(a['durum']),
                const SizedBox(width: 8),
                Text('Bildiren: ${a['bildiren_adi'] ?? '-'}',
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
              ]),
              const SizedBox(height: 10),
              Text(a['aciklama'] ?? 'Açıklama yok',
                  style: const TextStyle(fontSize: 14, height: 1.4, color: AppTheme.textDark)),
              if (a['teknik_notu'] != null && '${a['teknik_notu']}'.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Teknik notu: ${a['teknik_notu']}',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4)),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                if (a['fotograf_url'] != null && '${a['fotograf_url']}'.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _fotoGoster(a['fotograf_url'], 'Arıza Fotoğrafı'),
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('Arıza Foto'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  ),
                if (a['cozum_fotograf_url'] != null && '${a['cozum_fotograf_url']}'.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _fotoGoster(a['cozum_fotograf_url'], 'Çözüm Fotoğrafı'),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Çözüm Foto'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  ),
              ]),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
      ),
    );
  }
}
