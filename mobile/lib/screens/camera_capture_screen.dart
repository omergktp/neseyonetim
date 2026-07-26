import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;

import '../services/camera_service.dart';
import '../theme/app_theme.dart';
import '../utils/ui_utils.dart';

/// Tam ekran kamera çekim ekranı. Çekilen fotoğrafın dosya yolunu (String) döndürür.
/// Kullanıcı geri çıkarsa null döner. (Kural 2: sadece kamera, galeri yok.)
class CameraCaptureScreen extends StatefulWidget {
  final String title;
  const CameraCaptureScreen({Key? key, this.title = 'Fotoğraf Çek'}) : super(key: key);

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _cam;
  bool _ready = false;
  bool _capturing = false;
  String? _hata;        // kamera açılamadıysa gösterilecek mesaj
  bool _izinSorunu = false; // izin reddi: "Ayarlar'ı Aç" butonu göster

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  // Kamera açılamazsa (izin reddi, kamerasız cihaz, başka uygulama kullanıyor)
  // sonsuz "başlatılıyor" yerine açıklama + çözüm butonları gösterilir.
  Future<void> _init() async {
    setState(() {
      _ready = false;
      _hata = null;
      _izinSorunu = false;
    });
    try {
      final cams = await CameraService.getCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _hata = 'Bu cihazda kullanılabilir kamera bulunamadı.');
        return;
      }
      _cam = CameraController(cams[0], ResolutionPreset.veryHigh, enableAudio: false);
      await _cam!.initialize();
      if (mounted) setState(() => _ready = true);
    } on CameraException catch (e) {
      if (!mounted) return;
      final izin = e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt';
      setState(() {
        _izinSorunu = izin;
        _hata = izin
            ? 'Kamera izni verilmemiş. Fotoğraflı kanıt için kamera izni gerekli.'
            : 'Kamera başlatılamadı: ${e.description ?? e.code}';
      });
    } catch (e) {
      if (mounted) setState(() => _hata = 'Kamera başlatılamadı: $e');
    }
  }

  // Uygulama arka plana alınınca kamerayı bırak, dönünce yeniden başlat
  // (bazı cihazlarda controller askıda kalıp siyah ekran bırakıyordu).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _cam = null;
      if (mounted) setState(() => _ready = false);
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (!_ready || _cam == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final XFile photo = await _cam!.takePicture();
      if (mounted) Navigator.pop(context, photo.path);
    } catch (e) {
      if (mounted) {
        setState(() => _capturing = false);
        UiUtils.showSnackBar('Fotoğraf çekilemedi: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: _ready
          ? _buildCameraView()
          : (_hata != null ? _buildErrorView() : _buildLoadingView()),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _ready ? _buildShutterButton() : null,
    );
  }

  // Kamera açılamadı: açıklama + "Tekrar Dene" (+ izin sorununda "Ayarlar'ı Aç").
  Widget _buildErrorView() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 44),
            const SizedBox(height: 14),
            Text(
              _hata ?? 'Kamera başlatılamadı.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 18),
            if (_izinSorunu) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Geolocator.openAppSettings(),
                  icon: const Icon(Icons.settings),
                  label: const Text('Ayarlar\'ı Aç'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _init,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Kamera hazır değilken AppTheme.loadingBox ile tutarlı yükleme durumu.
  Widget _buildLoadingView() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
              ),
              const SizedBox(height: 14),
              const Text(
                'Kamera başlatılıyor...',
                style: TextStyle(color: Colors.white70, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Önizleme + üst rehber paneli + isteğe bağlı çekim overlay'i.
  Widget _buildCameraView() {
    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(_cam!)),

        // Üst rehber paneli — AppTheme.infoPanel tasarım diline uygun gradient şerit.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.70),
                  Colors.black.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Net bir fotoğraf çek. Tarih, saat ve konum otomatik olarak fotoğrafa eklenecek.',
                      style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Çekim sırasında işleme overlay'i.
        if (_capturing)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 32),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Fotoğraf işleniyor...',
                        style: TextStyle(color: Colors.white, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Çekim (shutter) butonu — AppTheme primary rengiyle uyumlu, dokunma alanı korunmuş.
  Widget _buildShutterButton() {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: _capturing ? null : _capture,
      child: AnimatedOpacity(
        opacity: _capturing ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary.withValues(alpha: 0.30),
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(shape: BoxShape.circle, color: primary),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
