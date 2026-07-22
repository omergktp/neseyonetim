import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../services/api_service.dart';
import '../services/camera_service.dart';
import '../services/location_service.dart';
import '../services/offline_queue.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/ui_utils.dart';

class ReportFaultScreen extends StatefulWidget {
  const ReportFaultScreen({super.key});

  @override
  State<ReportFaultScreen> createState() => _ReportFaultScreenState();
}

class _ReportFaultScreenState extends State<ReportFaultScreen> {
  final _baslikController = TextEditingController();
  final _aciklamaController = TextEditingController();

  List<dynamic> _sites = [];
  int? _siteId;

  CameraController? _cam;
  bool _camReady = false;
  bool _camError = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSites();
    _initCam();
  }

  Future<void> _loadSites() async {
    final sites = await ApiService.getSites();
    if (!mounted) return;
    if (sites == null) {
      UiUtils.showSnackBar('Tesis listesi yüklenemedi, bağlantıyı kontrol edin.', isError: true);
      return;
    }
    setState(() {
      _sites = sites;
      if (_sites.isNotEmpty) _siteId = int.tryParse(_sites.first['id'].toString());
    });
  }

  Future<void> _initCam() async {
    if (mounted && _camError) setState(() => _camError = false);
    try {
      final cameras = await CameraService.getCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _camError = true);
        return;
      }
      _cam = CameraController(cameras[0], ResolutionPreset.veryHigh, enableAudio: false);
      await _cam!.initialize();
      if (mounted) setState(() => _camReady = _cam?.value.isInitialized ?? false);
    } catch (e) {
      debugPrint('Kamera hatası: $e');
      if (mounted) {
        setState(() => _camError = true);
        UiUtils.showSnackBar('Kamera başlatılamadı. İzinleri kontrol edin.', isError: true);
      }
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    _baslikController.dispose();
    _aciklamaController.dispose();
    super.dispose();
  }

  void _msg(String m, {bool error = false}) {
    if (!mounted) return;
    UiUtils.showSnackBar(m, isError: error);
  }

  Future<void> _submit() async {
    if (_baslikController.text.trim().isEmpty) {
      _msg('Arıza başlığı boş bırakılamaz.', error: true);
      return;
    }
    if (_siteId == null) {
      _msg('Lütfen tesis seçin.', error: true);
      return;
    }

    setState(() => _loading = true);
    try {
      // Foto (varsa) çek -> filigranla (Kural 4) -> base64
      String? base64Image;
      if (_camReady && _cam != null) {
        final XFile photo = await _cam!.takePicture();
        final pos = await LocationService.getCurrentLocation();
        await CameraService.addWatermark(photo.path, pos?.latitude, pos?.longitude);
        final bytes = await File(photo.path).readAsBytes();
        base64Image = base64Encode(bytes);
      }

      final body = <String, dynamic>{
        'site_id': _siteId,
        'baslik': _baslikController.text.trim(),
        if (_aciklamaController.text.trim().isNotEmpty) 'aciklama': _aciklamaController.text.trim(),
        if (base64Image != null) 'fotograf_url': base64Image,
      };

      // KURAL 3 (Offline-first): İnternet yoksa veya sunucuya ulaşılamazsa
      // kaydı kaybetme — kuyruğa al, bağlantı gelince otomatik gönderilir.
      if (!await SyncService.hasInternet()) {
        await OfflineQueue.addRequest('report_fault.php', body);
        if (!mounted) return;
        _msg('İnternet yok: arıza kaydı kuyruğa alındı, bağlantı gelince gönderilecek.');
        Navigator.pop(context);
        return;
      }

      final sonuc = await ApiService.postQueued('report_fault.php', body);
      if (!mounted) return;
      if (sonuc == 'ok') {
        _msg('Arıza bildirildi.');
        Navigator.pop(context);
      } else if (sonuc == 'retry') {
        await OfflineQueue.addRequest('report_fault.php', body);
        if (!mounted) return;
        _msg('Sunucuya ulaşılamadı: kayıt kuyruğa alındı, bağlantı gelince gönderilecek.');
        Navigator.pop(context);
      } else {
        _msg('Arıza bildirilemedi. Bilgileri kontrol edin.', error: true);
      }
    } catch (e) {
      _msg('Hata: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static OutlineInputBorder _ob(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );

  @override
  Widget build(BuildContext context) {
    final seed = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arıza Bildir'),
        flexibleSpace: AppTheme.appBarFlex(seed),
      ),
      body: _loading
          ? AppTheme.loadingBox('Arıza bildiriliyor...', color: AppTheme.danger)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bilgilendirme paneli — AppTheme.infoPanel ile standardize
                  AppTheme.infoPanel(
                    icon: Icons.report_problem_outlined,
                    color: AppTheme.danger,
                    title: 'Dikkat',
                    text:
                        'Arızayı net açıkla ve mümkünse fotoğrafla. Kayıt yöneticiye ve ilgili teknik personele iletilecek.',
                  ),
                  const SizedBox(height: 20),

                  // Tesis alanı
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppTheme.sectionLabel('Tesis', icon: Icons.location_city_outlined),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _siteId,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.fieldFill,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: _ob(AppTheme.border),
                      enabledBorder: _ob(AppTheme.border),
                      focusedBorder: _ob(seed, 1.6),
                    ),
                    items: _sites
                        .map((s) => DropdownMenuItem<int>(
                              value: int.tryParse(s['id'].toString()),
                              child: Text(s['ad'] ?? '-'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _siteId = v),
                  ),
                  const SizedBox(height: 16),

                  // Arıza başlığı alanı
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppTheme.sectionLabel('Arıza Başlığı', icon: Icons.title_outlined),
                  ),
                  TextField(
                    controller: _baslikController,
                    decoration: const InputDecoration(hintText: 'Örn: B Blok asansör çalışmıyor'),
                  ),
                  const SizedBox(height: 16),

                  // Açıklama alanı
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppTheme.sectionLabel('Açıklama', icon: Icons.notes_outlined),
                  ),
                  TextField(
                    controller: _aciklamaController,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Sorunu detaylandır (isteğe bağlı)'),
                  ),
                  const SizedBox(height: 16),

                  // Fotoğraf / kamera alanı
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppTheme.sectionLabel('Fotoğraf (kamera)', icon: Icons.camera_alt_outlined),
                  ),
                  if (_camReady)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        children: [
                          SizedBox(height: 240, width: double.infinity, child: CameraPreview(_cam!)),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Arıza fotoğrafı',
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      height: 240,
                      decoration: BoxDecoration(
                        color: AppTheme.fieldFill,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: _camError
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.no_photography_outlined, size: 36, color: AppTheme.textMuted),
                                  const SizedBox(height: 8),
                                  const Text('Kamera açılamadı (fotoğrafsız da bildirebilirsin)',
                                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: _initCam,
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('Tekrar Dene'),
                                  ),
                                ],
                              ),
                            )
                          : AppTheme.loadingBox('Kamera hazırlanıyor...'),
                    ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.report_problem),
                      label: const Text('Arızayı Bildir', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
