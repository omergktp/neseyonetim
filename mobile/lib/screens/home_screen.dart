import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/offline_queue.dart';
import '../services/sync_service.dart';
import '../services/fcm_service.dart';
import '../theme/app_theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/ui_kit.dart';
import 'login_screen.dart';
import 'task_detail_screen.dart';
import 'report_fault_screen.dart';
import 'faults_screen.dart';

class HomeScreen extends StatefulWidget {
  final String themeColor;
  const HomeScreen({Key? key, required this.themeColor}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<dynamic> _tasks = [];
  bool _isLoading = true;
  String? _yuklemeHatasi; // null: sorun yok; dolu: liste yüklenemedi (boş listeyle karışmasın)
  int _bugunTamamlanan = 0; // gün sonu "işimi bitirdim" sayacı
  int _bekleyenKuyruk = 0;  // offline kuyrukta gönderilmeyi bekleyen kayıt sayısı
  int _olenKayit = 0;       // sunucunun kalıcı reddettiği (dead-letter) kayıt sayısı

  List<dynamic> _faults = [];
  bool _faultsLoading = false;

  String? _rol; // teknik ise sekmeli (Görevlerim / Arızalarım) görünüm
  String _ad = ''; // hero başlıktaki kişisel karşılama için (ad_soyad'ın ilk kelimesi)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiService.getRole().then((r) {
      if (!mounted) return;
      setState(() => _rol = r);
      if (r == 'teknik') _loadFaults();
    });
    SharedPreferences.getInstance().then((prefs) {
      final adSoyad = (prefs.getString('ad_soyad') ?? '').trim();
      if (adSoyad.isNotEmpty && mounted) {
        setState(() => _ad = adSoyad.split(' ').first);
      }
    });
    _loadTasks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadTasks();
      if (_rol == 'teknik') _loadFaults();
    }
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);

    // Bekleyen offline görevleri önce sunucuya göndermeyi dene
    final gonderilen = await SyncService.flushQueue();
    if (gonderilen > 0 && mounted) {
      UiUtils.showSnackBar('$gonderilen bekleyen görev sunucuya gönderildi.');
    }

    // Offline kuyrukta bekleyen kayıt sayısı (rozet için)
    final bekleyen =
        (await OfflineQueue.getQueue()).length + (await OfflineQueue.getRequests()).length;
    // Sunucunun kalıcı reddettiği kayıtlar (dead-letter): sessizce kaybolmaz,
    // personel uyarı rozetinden görür.
    final olen = (await OfflineQueue.getDeadLetters()).length;

    final result = await ApiService.getTasks();
    if (!mounted) return;
    _bekleyenKuyruk = bekleyen;
    _olenKayit = olen;
    if (result['success']) {
      setState(() {
        _tasks = result['tasks'];
        _bugunTamamlanan = (result['bugunTamamlanan'] as num?)?.toInt() ?? 0;
        _isLoading = false;
        _yuklemeHatasi = null;
      });
    } else {
      setState(() {
        _isLoading = false;
        _yuklemeHatasi = result['message']?.toString() ?? 'Görevler yüklenemedi.';
      });
      if (result['sessionExpired'] == true) {
        _oturumDustu();
        return;
      }
      UiUtils.showSnackBar(result['message'], isError: true);
    }
  }

  // Sunucunun kalıcı reddettiği kayıtların listesi: personel neyin
  // gönderilemediğini görür ve gerekiyorsa kaydı elle yeniden oluşturur.
  Future<void> _olenKayitlariGoster() async {
    final kayitlar = await OfflineQueue.getDeadLetters();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gönderilemeyen Kayıtlar'),
        content: SizedBox(
          width: double.maxFinite,
          child: kayitlar.isEmpty
              ? const Text('Gönderilemeyen kayıt yok.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: kayitlar.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) => Text(
                    '• ${kayitlar[i]['ozet']}',
                    style: const TextStyle(fontSize: 13.5, height: 1.4),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await OfflineQueue.clearDeadLetters();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() => _olenKayit = 0);
            },
            child: const Text('Listeyi Temizle'),
          ),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
        ],
      ),
    );
  }

  // Token süresi dolduğunda: oturumu temizle ve login'e dön (tema/IP korunur).
  void _oturumDustu() async {
    await ApiService.clearSession();
    if (!mounted) return;
    UiUtils.showSnackBar('Oturumunun süresi doldu, lütfen tekrar giriş yap.', isError: true);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  Future<void> _loadFaults() async {
    setState(() => _faultsLoading = true);
    final f = await ApiService.getFaults();
    if (mounted) {
      setState(() {
        if (f != null) _faults = f; // null: yüklenemedi, eldeki listeyi koru
        _faultsLoading = false;
      });
      if (f == null) {
        UiUtils.showSnackBar('Arıza listesi yüklenemedi, bağlantıyı kontrol edin.', isError: true);
      }
    }
  }

  void _logout() async {
    // Gönderilmemiş kuyruk varsa özellikle uyar: çıkış sonrası bu kayıtlar
    // ancak AYNI kullanıcı yeniden giriş yapınca gönderilebilir (başka hesabın
    // kimliğiyle asla gönderilmez).
    final bekleyen =
        (await OfflineQueue.getQueue()).length + (await OfflineQueue.getRequests()).length;
    if (!mounted) return;
    final kuyrukUyarisi = bekleyen > 0
        ? '\n\n⚠️ Gönderilmemiş $bekleyen kayıt var! Çıkarsan bu kayıtlar sen tekrar '
            'giriş yapana kadar gönderilemez. Mümkünse önce internet varken '
            '"Yenile"ye basıp kuyruğun boşalmasını bekle.'
        : '';
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: Text(
          'Çıkış yaparsan bu cihaza yeni görev bildirimleri GELMEZ. '
          'Vardiyan bittiyse çıkış yapmana gerek yok, uygulamayı kapatman yeterli.'
          '$kuyrukUyarisi\n\n'
          'Yine de çıkmak istiyor musun?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (onay != true) return;

    await FcmService.clearToken();
    final prefs = await SharedPreferences.getInstance();
    // Marka bilgileri (renk/ad/logo) çıkışta korunur: login ekranı firmanın
    // kimliğiyle açılmaya devam eder ("uygulama bizim" hissi).
    final tema = prefs.getString('theme_color');
    final firmaAd = prefs.getString('firma_ad');
    final logo = prefs.getString('firma_logo_url');
    await prefs.clear();
    if (tema != null) await prefs.setString('theme_color', tema);
    if (firmaAd != null) await prefs.setString('firma_ad', firmaAd);
    if (logo != null) await prefs.setString('firma_logo_url', logo);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  Color _getPrimaryColor() => AppTheme.parseHex(widget.themeColor);

  @override
  Widget build(BuildContext context) {
    final primaryColor = _getPrimaryColor();

    // FAB firma rengini kullanır; kırmızı yalnızca gerçekten yıkıcı işlemlere saklanır
    // (firma rengi kırmızı/turuncu olan tenant'larda görsel çakışmayı da önler).
    final fab = _gradientFab(primaryColor);

    // TEKNİK: sekmeli görünüm (Görevlerim / Arızalarım)
    if (_rol == 'teknik') {
      return DefaultTabController(
        length: 2,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            floatingActionButton: fab,
            body: Column(
              children: [
                HeroHeader(
                  seed: primaryColor,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _heroTitleRow(),
                      const SizedBox(height: 14),
                      _heroStats(),
                      const SizedBox(height: 12),
                      _heroTabBar(),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildTasksBody(primaryColor),
                      _buildFaultsBody(primaryColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // DİĞER ROLLER: sadece görev listesi
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        floatingActionButton: fab,
        body: Column(
          children: [
            HeroHeader(
              seed: primaryColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heroTitleRow(),
                  const SizedBox(height: 16),
                  _heroStats(),
                ],
              ),
            ),
            Expanded(child: _buildTasksBody(primaryColor)),
          ],
        ),
      ),
    );
  }

  // ---- Hero başlık içeriği ----

  // Üst satır: tarih + kişisel karşılama solda, aksiyon ikonları sağda.
  Widget _heroTitleRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                turkceTarih(DateTime.now()).toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _ad.isEmpty ? 'İş Emirlerim' : 'Merhaba, $_ad 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        // Dead-letter uyarısı: sunucunun reddettiği kayıtlar sessizce kaybolmaz.
        if (_olenKayit > 0)
          _heroIcon(
            tooltip: 'Gönderilemeyen kayıtlar',
            onTap: _olenKayitlariGoster,
            child: Badge(
              label: Text('$_olenKayit'),
              backgroundColor: Colors.red,
              child: const Icon(Icons.error_outline, color: Colors.white, size: 22),
            ),
          ),
        // Offline kuyruk rozeti: personel "kaydım kayboldu mu?" endişesi yaşamasın.
        if (_bekleyenKuyruk > 0)
          _heroIcon(
            tooltip: 'Gönderilmeyi bekleyen kayıtlar',
            onTap: () {
              UiUtils.showSnackBar(
                  '$_bekleyenKuyruk kayıt cihazda güvende; internet gelince otomatik gönderilecek.');
            },
            child: Badge(
              label: Text('$_bekleyenKuyruk'),
              child: const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 22),
            ),
          ),
        _heroIcon(
          tooltip: 'Yenile',
          onTap: () {
            _loadTasks();
            if (_rol == 'teknik') _loadFaults();
          },
          child: const Icon(Icons.refresh, color: Colors.white, size: 22),
        ),
        _heroIcon(
          tooltip: 'Çıkış',
          onTap: _logout,
          child: const Icon(Icons.logout, color: Colors.white, size: 20),
        ),
      ],
    );
  }

  // Hero üstündeki yuvarlak cam aksiyon butonu.
  Widget _heroIcon({required Widget child, required VoidCallback onTap, String? tooltip}) {
    final buton = Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Center(child: child)),
        ),
      ),
    );
    return tooltip == null ? buton : Tooltip(message: tooltip, child: buton);
  }

  // "Bugünün işleri" cam istatistik kutuları (hero içinde).
  Widget _heroStats() {
    final devam = _tasks.where((t) => t['durum'] == 'devam_ediyor').length;
    final bekleyen = _tasks.where((t) => t['durum'] == 'bekliyor').length;
    return Row(
      children: [
        GlassStat(value: '$devam', label: 'Devam eden', icon: Icons.play_circle_fill),
        const SizedBox(width: 10),
        GlassStat(value: '$bekleyen', label: 'Bekleyen', icon: Icons.schedule),
        const SizedBox(width: 10),
        GlassStat(value: '$_bugunTamamlanan', label: 'Bugün biten', icon: Icons.check_circle),
      ],
    );
  }

  // Teknik roldeki sekmeler: hero içinde hap (pill) görünümlü TabBar.
  Widget _heroTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(16),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        tabs: const [
          Tab(height: 44, icon: Icon(Icons.assignment, size: 18), text: 'Görevlerim'),
          Tab(height: 44, icon: Icon(Icons.handyman, size: 18), text: 'Arızalarım'),
        ],
      ),
    );
  }

  // Arıza bildir: marka gradyanlı özel FAB.
  Widget _gradientFab(Color primary) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient(primary),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: primary.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
                context, MaterialPageRoute(builder: (context) => const ReportFaultScreen()));
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.report_problem, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Arıza Bildir',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Görev kartındaki checklist (alt görev) ilerleme çubuğu.
  Widget _checklistProgress(Map task, Color primary) {
    final list = (task['alt_gorevler'] as List?) ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final toplam = list.length;
    final yapilan = list.where((g) => g['yapildi_mi'].toString() == '1').length;
    final oran = toplam == 0 ? 0.0 : yapilan / toplam;
    final bitti = yapilan == toplam;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rtl, size: 15, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              const Text('Checklist', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('$yapilan/$toplam adım',
                  style: TextStyle(color: bitti ? AppTheme.success : AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: oran,
              minHeight: 6,
              backgroundColor: AppTheme.border,
              valueColor: AlwaysStoppedAnimation(bitti ? AppTheme.success : primary),
            ),
          ),
        ],
      ),
    );
  }

  // Tek görev kartı: ikonlu avatar + başlık + tesis + durum + ilerleme + eylem.
  Widget _taskCard(dynamic task, int index, Color primary) {
    final devam = task['durum'] == 'devam_ediyor';
    final grad = AppTheme.brandGradient(primary);
    void ac() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => TaskDetailScreen(task: task)),
      ).then((value) => _loadTasks());
    }

    return FadeSlideIn(
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: AppTheme.cardDecoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: ac,
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: grad.colors.map((c) => c.withValues(alpha: 0.14)).toList(),
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(devam ? Icons.autorenew : Icons.assignment_outlined,
                            color: devam ? AppTheme.warning : primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task['baslik'] ?? 'Başlıksız Görev',
                              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textMuted),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    task['site_adi'] ?? 'Belirtilmemiş Tesis',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusUi.chip(task['durum']),
                    ],
                  ),
                  _checklistProgress(task, primary),
                  const SizedBox(height: 16),
                  GradientButton(
                    onPressed: ac,
                    seed: primary,
                    height: 46,
                    icon: devam ? Icons.arrow_forward : Icons.play_arrow,
                    label: devam ? 'Göreve Devam Et' : 'Görevi Başlat',
                    colors: devam ? const [AppTheme.warning, Color(0xFFB45309)] : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Görev listesi ----
  Widget _buildTasksBody(Color primaryColor) {
    return RefreshIndicator(
      onRefresh: _loadTasks,
      color: primaryColor,
      child: _isLoading
          ? SkeletonPulse(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [SkeletonCard(), SkeletonCard(), SkeletonCard(), SkeletonCard()],
              ),
            )
          : _tasks.isEmpty
              ? (_yuklemeHatasi != null
                  ? AppTheme.emptyState(
                      icon: Icons.wifi_off_outlined,
                      title: 'Görevler yüklenemedi',
                      subtitle: '$_yuklemeHatasi\nAşağı çekerek tekrar deneyebilirsin.',
                      accent: AppTheme.danger,
                    )
                  : AppTheme.emptyState(
                      icon: Icons.assignment_turned_in_outlined,
                      title: 'Atanmış görev yok',
                      subtitle: 'Şu an sana atanmış bir iş emri bulunmuyor. Aşağı çekerek yenileyebilirsin.',
                      accent: primaryColor,
                    ))
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _tasks.length,
                  itemBuilder: (context, index) =>
                      _taskCard(_tasks[index], index, primaryColor),
                ),
    );
  }

  // ---- Arıza listesi (teknik) ----
  Widget _buildFaultsBody(Color primaryColor) {
    return RefreshIndicator(
      onRefresh: _loadFaults,
      color: primaryColor,
      child: _faultsLoading
          ? SkeletonPulse(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [SkeletonCard(), SkeletonCard(), SkeletonCard()],
              ),
            )
          : _faults.isEmpty
              ? AppTheme.emptyState(
                  icon: Icons.handyman_outlined,
                  title: 'Açık arıza yok',
                  subtitle: 'Sana atanmış açık bir arıza kaydı bulunmuyor. Aşağı çekerek yenileyebilirsin.',
                  accent: primaryColor,
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _faults.length,
                  itemBuilder: (context, i) {
                    final a = _faults[i];
                    final bekliyor = a['durum'] == 'bekliyor';
                    return FadeSlideIn(
                      index: i,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: AppTheme.cardDecoration,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => FaultDetailScreen(fault: a)),
                              );
                              _loadFaults();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                        color: AppTheme.danger.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(14)),
                                    child: Icon(bekliyor ? Icons.hourglass_bottom : Icons.warning_amber_rounded,
                                        color: AppTheme.danger),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(a['baslik'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark)),
                                        const SizedBox(height: 4),
                                        Text(a['site_adi'] ?? 'Tesis', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                                        const SizedBox(height: 8),
                                        StatusUi.chip(a['durum']),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
