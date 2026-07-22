import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/camera_service.dart';
import '../services/offline_queue.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/ui_utils.dart';
import 'qr_scan_screen.dart';
import 'expense_screen.dart';

class TaskDetailScreen extends StatefulWidget {
  final Map<String, dynamic> task;
  const TaskDetailScreen({Key? key, required this.task}) : super(key: key);

  @override
  _TaskDetailScreenState createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _camError = false;
  bool _isLoading = false;
  late String _durum; // 'bekliyor' iken başlatma, 'devam_ediyor' iken tamamlama ekranı
  String? _rol; // teknik personele "Masraf Ekle" göstermek için

  @override
  void initState() {
    super.initState();
    _durum = (widget.task['durum']?.toString() ?? 'bekliyor');
    // Kamerayı yalnızca görev BAŞLADIYSA aç. "bekliyor" iken açmıyoruz; aksi halde
    // QR tarayıcı (mobile_scanner) kamerayı isteyince çakışır ve dönüşte önizleme donar.
    if (_durum != 'bekliyor') _ensureCamera();
    ApiService.getRole().then((r) {
      if (mounted) setState(() => _rol = r);
    });
  }

  // Kamerayı (gerekiyorsa) başlatır. Birden çok kez çağrılması güvenlidir.
  Future<void> _ensureCamera() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) return;
    if (mounted && _camError) setState(() => _camError = false);
    try {
      final cameras = await CameraService.getCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _camError = true);
        return;
      }
      _cameraController = CameraController(
        cameras[0],
        ResolutionPreset.veryHigh, // 1080p — daha net ve geniş açı
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint('Kamera başlatılamadı: $e');
      if (mounted) {
        setState(() => _camError = true);
        UiUtils.showSnackBar('Kamera başlatılamadı, izinleri kontrol edin.', isError: true);
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // ---------------- GÖREV BAŞLATMA (QR veya Konum) ----------------

  // Sahada olma (50m) doğrulaması; uygunsa konumu döndürür (sunucuya da gönderilir).
  // Başarısızsa kullanıcıyı yalnız bırakmaz: kaç metre uzakta olduğunu söyler,
  // konum kapalıysa tek dokunuşla ayarlara götürür.
  Future<Position?> _konumDogrula() async {
    final position = await LocationService.getCurrentLocation();
    if (position == null) {
      if (!mounted) return null;
      UiUtils.showSnackBar(
        LocationService.sonHata ?? 'Konum bilgisi alınamadı. Konum servislerini açın.',
        isError: true,
        actionLabel: 'Ayarlar',
        onAction: LocationService.sonHataAyariniAc,
      );
      return null;
    }
    double siteLat = double.tryParse(widget.task['enlem']?.toString() ?? '0') ?? 0.0;
    double siteLng = double.tryParse(widget.task['boylam']?.toString() ?? '0') ?? 0.0;
    if (siteLat != 0 && siteLng != 0) {
      final mesafe = LocationService.calculateDistance(
          position.latitude, position.longitude, siteLat, siteLng);
      if (mesafe > 50) {
        _showError('Tesise ${mesafe.round()} m uzaktasın; en fazla 50 m yakında olmalısın.');
        return null;
      }
    } else {
      // Tesisin koordinatı tanımlı değil: mesafe doğrulanamıyor, kullanıcıyı bilgilendir.
      _showSuccess('Not: Tesis koordinatı tanımlı olmadığından mesafe doğrulanamadı.');
    }
    return position;
  }

  Future<void> _startWithQr() async {
    // QR tarayıcıyı aç; kullanıcı iptal ederse null döner
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (code == null) return;

    setState(() => _isLoading = true);
    try {
      await _callStart('qr', code);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startWithLocation() async {
    setState(() => _isLoading = true);
    try {
      final pos = await _konumDogrula();
      if (pos == null) return;
      await _callStart('konum', null, pos: pos);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _callStart(String yontem, String? qrDeger, {Position? pos}) async {
    final taskId = int.tryParse(widget.task['id'].toString()) ?? 0;
    final res = await ApiService.startTask(taskId, yontem,
        qrDeger: qrDeger, enlem: pos?.latitude, boylam: pos?.longitude);
    if (!mounted) return;
    if (res['success']) {
      HapticFeedback.mediumImpact();
      setState(() => _durum = 'devam_ediyor');
      _ensureCamera(); // tamamla adımına geçildi: kamerayı şimdi aç
      _showSuccess('Görev başlatıldı. Şimdi fotoğraf çekip tamamlayabilirsiniz.');
    } else {
      _showError(res['message']);
    }
  }

  // ---------------- GÖREV TAMAMLAMA ----------------

  Future<void> _completeTask() async {
    // 0. Checklist eksikse nazik onay iste (iş kalitesi güvencesi).
    final altGorevler = (widget.task['alt_gorevler'] as List?) ?? const [];
    final eksik = altGorevler.where((g) => g['yapildi_mi'].toString() != '1').length;
    if (eksik > 0) {
      final devamEt = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Eksik adım var'),
          content: Text('$eksik checklist adımı henüz işaretlenmedi. Yine de görevi tamamlamak istiyor musun?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Geri Dön')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yine de Tamamla')),
          ],
        ),
      );
      if (devamEt != true) return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Konum Doğrulaması (50 metre kuralı) — mesafe geri bildirimi ile
      final position = await _konumDogrula();
      if (position == null) return;

      // 2. Fotoğraf Çekimi (Kural 2: Galeri yasak)
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        _showError('Kamera başlatılamadı.');
        return;
      }

      // Çek -> filigranla -> önizle; net değilse tekrar çek.
      String? path;
      while (path == null) {
        final XFile photo = await _cameraController!.takePicture();
        HapticFeedback.mediumImpact(); // deklanşör hissi
        // 3. Filigran Ekle (Kural 4)
        await CameraService.addWatermark(photo.path, position.latitude, position.longitude);
        if (!mounted) return;
        final onay = await _fotoOnayla(photo.path);
        if (onay == null) return;      // kullanıcı vazgeçti
        if (onay) path = photo.path;   // false ise döngü tekrar çeker
      }

      // Fotoğrafı Base64'e çevir
      final bytes = await File(path).readAsBytes();
      String base64Image = base64Encode(bytes);

      // 4. İnternet Kontrolü (Kural 3: Offline-first)
      bool hasInternet = await SyncService.hasInternet();

      int taskId = int.tryParse(widget.task['id'].toString()) ?? 0;

      if (hasInternet) {
        final sonuc = await ApiService.saveTask(taskId, position.latitude, position.longitude, base64Image);
        if (sonuc == 'ok') {
          await _kutlamaGoster('Konum doğrulandı, kanıt fotoğrafı sunucuya iletildi.');
        } else if (sonuc == 'rejected') {
          // Sunucu kalıcı olarak reddetti (görev kapatılmış/iptal olabilir) — kuyruğa ALMA.
          _showError('Sunucu görevi kabul etmedi. Görev durumu değişmiş olabilir, listeyi yenileyin.');
          return;
        } else {
          await OfflineQueue.addToQueue(taskId, position.latitude, position.longitude, base64Image);
          await _kutlamaGoster('Sunucuya ulaşılamadı; kayıt cihazda güvende, internet gelince otomatik gönderilecek.');
        }
      } else {
        await OfflineQueue.addToQueue(taskId, position.latitude, position.longitude, base64Image);
        await _kutlamaGoster('İnternet yok; kayıt cihazda güvende, bağlantı gelince otomatik gönderilecek.');
      }

      if (mounted) Navigator.pop(context);

    } catch (e) {
      _showError('Görev kapatılırken hata oluştu: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Çekilen (filigranlı) fotoğrafın önizlemesi: bulanık kanıt yönetici tarafından
  // reddedilebilir; personele "Net mi?" diye tek bakışta karar şansı verir.
  // Dönüş: true = onaylandı, false = tekrar çek, null = vazgeçildi.
  Future<bool?> _fotoOnayla(String path) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fotoğraf net mi?'),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(path), height: 280, width: double.maxFinite, fit: BoxFit.cover),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, false),
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar Çek'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check),
            label: const Text('Onayla'),
          ),
        ],
      ),
    );
  }

  // Tamamlama kutlaması: emeğin görünür olduğu, "işimi kanıtladım" anı.
  Future<void> _kutlamaGoster(String altMetin) async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    final saat = TimeOfDay.now().format(context);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (context, value, child) => Transform.scale(scale: value, child: child),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: AppTheme.success, size: 56),
              ),
            ),
            const SizedBox(height: 16),
            Text('Görev Tamamlandı!', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('Saat $saat', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 10),
            Text(altMetin,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textDark, fontSize: 13.5, height: 1.4)),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white),
              child: const Text('Harika!'),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    UiUtils.showSnackBar(msg, isError: true);
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    UiUtils.showSnackBar(msg);
  }

  // ---------------- ARAYÜZ ----------------

  Color get _primary => Theme.of(context).colorScheme.primary;

  // Adım göstergesi: 1. Başlat → 2. Tamamla
  Widget _stepIndicator(bool basladi) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          _step(1, 'Başlat', tamam: basladi, aktif: !basladi),
          _connector(basladi),
          _step(2, 'Tamamla', tamam: false, aktif: basladi),
        ],
      ),
    );
  }

  Widget _step(int no, String etiket, {required bool tamam, required bool aktif}) {
    final renk = tamam ? AppTheme.success : (aktif ? _primary : AppTheme.border);
    final yaziRenk = tamam || aktif ? AppTheme.textDark : AppTheme.textMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
          child: Center(
            child: tamam
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text('$no', style: TextStyle(color: aktif ? Colors.white : AppTheme.textMuted, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 6),
        Text(etiket, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: yaziRenk)),
      ],
    );
  }

  Widget _connector(bool basladi) {
    return Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.only(bottom: 22),
        color: basladi ? AppTheme.success : AppTheme.border,
      ),
    );
  }

  // Başlık kartı: tesis + durum rozeti + açıklama
  Widget _headerCard() {
    final aciklama = (widget.task['aciklama']?.toString() ?? '').trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, size: 18, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(widget.task['site_adi'] ?? 'Tesis',
                    style: const TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              StatusUi.chip(_durum),
            ],
          ),
          if (aciklama.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(aciklama, style: const TextStyle(fontSize: 15, color: AppTheme.textDark, height: 1.4)),
          ],
        ],
      ),
    );
  }

  // Bir checklist maddesini işaretle/kaldır — iyimser güncelle, hata olursa geri al.
  Future<void> _toggleSubtask(Map g) async {
    final id = int.tryParse(g['id'].toString()) ?? 0;
    if (id == 0) return;
    HapticFeedback.selectionClick(); // eldivenli kullanımda "işaretlendi" hissi
    final eski = g['yapildi_mi'].toString() == '1';
    final yeni = !eski;
    setState(() => g['yapildi_mi'] = yeni ? 1 : 0);
    final ok = await ApiService.updateSubtask(id, yeni);
    if (!ok && mounted) {
      setState(() => g['yapildi_mi'] = eski ? 1 : 0);
      UiUtils.showSnackBar('Adım kaydedilemedi, tekrar deneyin.', isError: true);
      return;
    }
    // Son adım da işaretlendiyse küçük bir kutlama titreşimi (tamamlamaya doğal geçiş).
    final list = (widget.task['alt_gorevler'] as List?) ?? const [];
    if (yeni && list.isNotEmpty && list.every((x) => x['yapildi_mi'].toString() == '1')) {
      HapticFeedback.mediumImpact();
    }
  }

  // Görevin kontrol listesi (alt görevler) — personel dokununca işaretler, sunucuya kaydedilir.
  Widget _checklistCard() {
    final list = (widget.task['alt_gorevler'] as List?) ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final toplam = list.length;
    final yapilan = list.where((g) => g['yapildi_mi'].toString() == '1').length;
    final bitti = yapilan == toplam;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: AppTheme.sectionLabel('Kontrol Listesi', icon: Icons.checklist_rtl),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Text('$yapilan/$toplam',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: bitti ? AppTheme.success : _primary)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: toplam == 0 ? 0 : yapilan / toplam,
                  minHeight: 6,
                  backgroundColor: AppTheme.border,
                  valueColor: AlwaysStoppedAnimation(bitti ? AppTheme.success : _primary),
                ),
              ),
              const SizedBox(height: 6),
              ...list.map((g) {
                final yapildi = g['yapildi_mi'].toString() == '1';
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _toggleSubtask(g),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            yapildi ? Icons.check_circle : Icons.radio_button_unchecked,
                            key: ValueKey(yapildi),
                            size: 24,
                            color: yapildi ? AppTheme.success : AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            g['gorev_metni']?.toString() ?? '-',
                            style: TextStyle(
                              fontSize: 14.5,
                              color: yapildi ? AppTheme.textMuted : AppTheme.textDark,
                              decoration: yapildi ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // Görev henüz başlamadıysa: QR / Konum ile başlatma kartı
  Widget _buildStartPanel() {
    return Padding(
      key: const ValueKey('start'),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTheme.infoPanel(
            icon: Icons.info_outline,
            color: _primary,
            text: 'Göreve başlamak için tesisteki QR kodu okutun. QR yoksa veya hasarlıysa konumunuzla doğrulayın.',
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _startWithQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('QR Okut ve Başlat', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _startWithLocation,
              icon: const Icon(Icons.location_on),
              label: const Text('QR Hasarlı – Konumla Başlat', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  // Görev başladıysa: kamera önizleme + tamamlama
  Widget _buildCompletePanel() {
    return Padding(
      key: const ValueKey('complete'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTheme.sectionLabel('Kapanış Fotoğrafı', icon: Icons.photo_camera),
          const SizedBox(height: 10),
          if (_isCameraInitialized)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  SizedBox(
                    height: 300,
                    width: double.infinity,
                    child: CameraPreview(_cameraController!),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_camera, color: Colors.white, size: 14),
                          SizedBox(width: 6),
                          Text('Kapanış fotoğrafı', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 300,
              decoration: BoxDecoration(color: AppTheme.fieldFill, borderRadius: BorderRadius.circular(18)),
              child: _camError
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.no_photography_outlined, size: 40, color: AppTheme.textMuted),
                          const SizedBox(height: 10),
                          const Text('Kamera açılamadı', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          const Text('Kamera iznini kontrol edip tekrar deneyin.',
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _ensureCamera,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tekrar Dene'),
                          ),
                        ],
                      ),
                    )
                  : AppTheme.loadingBox('Kamera hazırlanıyor...'),
            ),
          const SizedBox(height: 10),
          AppTheme.infoPanel(
            icon: Icons.verified_user_outlined,
            color: _primary,
            text: 'Tamamlamak için tesise en fazla 50 m yakında olmalısın; fotoğrafa konum ve saat eklenir.',
          ),
          if (_rol == 'teknik') ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final taskId = int.tryParse(widget.task['id'].toString()) ?? 0;
                  // Aynı anda iki kamera açılamaz: masraf ekranı kendi kamerasını
                  // kullanacağı için önce buradakini kapat, dönüşte yeniden aç.
                  final cam = _cameraController;
                  _cameraController = null;
                  setState(() => _isCameraInitialized = false);
                  await cam?.dispose();
                  if (!mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ExpenseScreen(isEmriId: taskId)),
                  );
                  if (mounted) _ensureCamera();
                },
                icon: const Icon(Icons.receipt_long),
                label: const Text('Masraf / Malzeme Ekle'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final basladi = _durum != 'bekliyor';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task['baslik'] ?? 'Görev Detayı'),
        flexibleSpace: AppTheme.appBarFlex(_primary),
      ),
      // Ana eylem her zaman başparmak bölgesinde: uzun checklist'te bile
      // scroll gerektirmeden tek elle erişilir.
      bottomNavigationBar: (basladi && !_isLoading)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _completeTask,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Görevi Tamamla', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success, foregroundColor: Colors.white),
                  ),
                ),
              ),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stepIndicator(basladi),
                  _headerCard(),
                  _checklistCard(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SizeTransition(sizeFactor: anim, axisAlignment: -1, child: child),
                    ),
                    child: basladi ? _buildCompletePanel() : _buildStartPanel(),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }
}
