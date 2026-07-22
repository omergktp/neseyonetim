import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';

/// Tam ekran QR okuyucu. Bir kod okunduğunda Navigator.pop ile kodu (String) döndürür.
/// Kullanıcı geri çıkarsa null döner.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({Key? key}) : super(key: key);

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false; // Aynı kodu iki kez işlemeyi engeller
  bool _torch = false;
  late final AnimationController _anim;

  static const double _frame = 260;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('QR kod okunamadı, tekrar deneyin.'),
              ],
            ),
            backgroundColor: AppTheme.danger,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _handled = true;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('QR Kodu Okut'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(
                _torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                color: _torch ? AppTheme.warning : Colors.white,
              ),
              tooltip: _torch ? 'Flaşı Kapat' : 'Flaşı Aç',
              style: IconButton.styleFrom(
                backgroundColor: _torch
                    ? AppTheme.warning.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.10),
                shape: const CircleBorder(),
              ),
              onPressed: () {
                _controller.toggleTorch();
                setState(() => _torch = !_torch);
              },
            ),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Çerçeve dışını karartan katman (delikli)
          Positioned.fill(child: CustomPaint(painter: _ScrimPainter(_frame))),

          // Köşe çerçeveleri + hareketli tarama çizgisi
          SizedBox(
            width: _frame,
            height: _frame,
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _CornerPainter(primary))),
                AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) {
                    return Positioned(
                      top: 10 + (_frame - 20) * _anim.value,
                      left: 16,
                      right: 16,
                      child: Container(
                        height: 2.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            primary.withValues(alpha: 0),
                            primary,
                            primary.withValues(alpha: 0),
                          ]),
                          boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.6), blurRadius: 8)],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Alt bilgilendirme paneli — AppTheme.infoPanel ile standardize
          Positioned(
            bottom: 56,
            left: 24,
            right: 24,
            child: _InfoOverlay(primary: primary),
          ),
        ],
      ),
    );
  }
}

/// Kamera önizlemesi üzerindeki bilgilendirme paneli.
/// Yarı saydam arka plan, AppTheme.infoPanel ruhuna uygun tasarım.
class _InfoOverlay extends StatelessWidget {
  final Color primary;
  const _InfoOverlay({required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withValues(alpha: 0.30), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.qr_code_scanner_rounded, color: primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'QR Kodu Tara',
                  style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(
                  'Tesisteki QR kodu çerçeve içine alın',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Çerçeve dışını karartan, ortada yuvarlak köşeli delik bırakan boyayıcı.
class _ScrimPainter extends CustomPainter {
  final double frame;
  _ScrimPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
      Rect.fromCenter(center: size.center(Offset.zero), width: frame, height: frame),
      const Radius.circular(20),
    );
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRRect(hole),
    );
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Çerçevenin dört köşesine L şeklinde köşe işaretleri çizer.
class _CornerPainter extends CustomPainter {
  final Color color;
  _CornerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 30.0;
    const r = 18.0;
    final w = size.width, h = size.height;

    canvas.drawPath(Path()..moveTo(0, len)..lineTo(0, r)..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))..lineTo(len, 0), p);
    canvas.drawPath(Path()..moveTo(w - len, 0)..lineTo(w - r, 0)..arcToPoint(Offset(w, r), radius: const Radius.circular(r))..lineTo(w, len), p);
    canvas.drawPath(Path()..moveTo(w, h - len)..lineTo(w, h - r)..arcToPoint(Offset(w - r, h), radius: const Radius.circular(r))..lineTo(w - len, h), p);
    canvas.drawPath(Path()..moveTo(len, h)..lineTo(r, h)..arcToPoint(Offset(0, h - r), radius: const Radius.circular(r))..lineTo(0, h - len), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
