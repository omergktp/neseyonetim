import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/fcm_service.dart';
import '../theme/app_theme.dart';
import '../utils/ui_utils.dart';
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

  List<dynamic> _faults = [];
  bool _faultsLoading = false;

  String? _rol; // teknik ise sekmeli (Görevlerim / Arızalarım) görünüm

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiService.getRole().then((r) {
      if (!mounted) return;
      setState(() => _rol = r);
      if (r == 'teknik') _loadFaults();
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

    final result = await ApiService.getTasks();
    if (!mounted) return;
    if (result['success']) {
      setState(() {
        _tasks = result['tasks'];
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
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text(
          'Çıkış yaparsan bu cihaza yeni görev bildirimleri GELMEZ. '
          'Vardiyan bittiyse çıkış yapmana gerek yok, uygulamayı kapatman yeterli.\n\n'
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
    await prefs.clear();
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
    final fab = FloatingActionButton.extended(
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const ReportFaultScreen()));
      },
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.report_problem),
      label: const Text('Arıza Bildir'),
    );

    final actions = [
      IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Yenile',
        onPressed: () {
          _loadTasks();
          if (_rol == 'teknik') _loadFaults();
        },
      ),
      IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
    ];

    // TEKNİK: sekmeli görünüm (Görevlerim / Arızalarım)
    if (_rol == 'teknik') {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          floatingActionButton: fab,
          appBar: AppBar(
            title: const Text('Glow Saha', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: primaryColor,
            flexibleSpace: AppTheme.appBarFlex(primaryColor),
            actions: actions,
            bottom: const TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                Tab(icon: Icon(Icons.assignment), text: 'Görevlerim'),
                Tab(icon: Icon(Icons.handyman), text: 'Arızalarım'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _buildTasksBody(primaryColor),
              _buildFaultsBody(primaryColor),
            ],
          ),
        ),
      );
    }

    // DİĞER ROLLER: sadece görev listesi
    return Scaffold(
      floatingActionButton: fab,
      appBar: AppBar(
        title: const Text('İş Emirlerim', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
        flexibleSpace: AppTheme.appBarFlex(primaryColor),
        actions: actions,
      ),
      body: _buildTasksBody(primaryColor),
    );
  }

  // ---- "Bugün" özet şeridi (görev listesinin üstünde) ----
  Widget _ozetSerit(Color primary) {
    final toplam = _tasks.length;
    final devam = _tasks.where((t) => t['durum'] == 'devam_ediyor').length;
    final bekleyen = _tasks.where((t) => t['durum'] == 'bekliyor').length;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, Color.lerp(primary, Colors.black, 0.28)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Text('Bugünün İşleri', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$toplam görev', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniStat(devam.toString(), 'Devam eden', Icons.play_circle_fill),
              const SizedBox(width: 10),
              _miniStat(bekleyen.toString(), 'Bekleyen', Icons.schedule),
              const SizedBox(width: 10),
              _miniStat(toplam.toString(), 'Toplam', Icons.assignment),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String deger, String etiket, IconData ikon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(ikon, color: Colors.white, size: 18),
            const SizedBox(height: 6),
            Text(deger, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(etiket, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
          ],
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

  // ---- Görev listesi ----
  Widget _buildTasksBody(Color primaryColor) {
    return RefreshIndicator(
      onRefresh: _loadTasks,
      color: primaryColor,
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
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
                  itemCount: _tasks.length + 1, // 0: özet şeridi
                  itemBuilder: (context, index) {
                    if (index == 0) return _ozetSerit(primaryColor);
                    final task = _tasks[index - 1];
                    final devam = task['durum'] == 'devam_ediyor';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: AppTheme.cardDecoration,
                      child: Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    task['baslik'] ?? 'Başlıksız Görev',
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                StatusUi.chip(task['durum']),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined, size: 16, color: AppTheme.textMuted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    task['site_adi'] ?? 'Belirtilmemiş Tesis',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            _checklistProgress(task, primaryColor),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => TaskDetailScreen(task: task)),
                                  ).then((value) => _loadTasks());
                                },
                                icon: Icon(devam ? Icons.arrow_forward : Icons.play_arrow, size: 20),
                                label: Text(devam ? 'Göreve Devam Et' : 'Görevi Başlat'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: devam ? AppTheme.warning : primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  // ---- Arıza listesi (teknik) ----
  Widget _buildFaultsBody(Color primaryColor) {
    return RefreshIndicator(
      onRefresh: _loadFaults,
      color: primaryColor,
      child: _faultsLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
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
                    return Container(
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
                    );
                  },
                ),
    );
  }
}
