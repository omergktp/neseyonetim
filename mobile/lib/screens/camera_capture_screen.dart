import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

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

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _cam;
  bool _ready = false;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cams = await CameraService.getCameras();
    if (cams.isNotEmpty) {
      _cam = CameraController(cams[0], ResolutionPreset.veryHigh, enableAudio: false);
      await _cam!.initialize();
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
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
      body: _ready ? _buildCameraView() : _buildLoadingView(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _ready ? _buildShutterButton() : null,
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
