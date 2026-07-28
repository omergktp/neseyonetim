import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Ortak "premium" görsel bileşenler: gradyan hero başlık, kademeli giriş
/// animasyonu, iskelet (skeleton) yükleme ve gradyan butonlar.
/// Amaç: login ekranındaki görsel kaliteyi iç ekranlara da taşımak.

/// Liste elemanlarına kademeli (staggered) fade + yukarı kayma girişi.
/// [index] arttıkça gecikme artar; 8'den sonrası aynı anda girer (uzun
/// listelerde sonsuz bekletme olmasın).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    _fade = curved;
    _slide = Tween<Offset>(begin: const Offset(0, 0.07), end: Offset.zero).animate(curved);
    Future.delayed(Duration(milliseconds: 55 * math.min(widget.index, 8)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// İskelet yükleme: içeriğin biçimini taklit eden, yumuşakça "nefes alan"
/// gri kutular. Spinner yerine kullanılır; ekran boş görünmez.
class SkeletonPulse extends StatefulWidget {
  final Widget child;
  const SkeletonPulse({super.key, required this.child});

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// İskelet parçası: yuvarlatılmış gri kutu.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width = double.infinity, required this.height, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.border,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Görev/arıza kartı biçiminde iskelet kart (liste yüklenirken).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              SkeletonBox(width: 46, height: 46, radius: 14),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 160, height: 16),
                    SizedBox(height: 8),
                    SkeletonBox(width: 110, height: 12),
                  ],
                ),
              ),
              SkeletonBox(width: 70, height: 24, radius: 12),
            ],
          ),
          SizedBox(height: 16),
          SkeletonBox(height: 44, radius: 14),
        ],
      ),
    );
  }
}

/// Gradyan hero başlık: AppBar yerine geçen, firma renginden türeyen
/// gradyanlı, alt köşeleri yuvarlak, ışıltı (blob) dokunuşlu başlık alanı.
/// [child] başlık satırı + istatistik/sekme gibi içerikleri alır.
class HeroHeader extends StatelessWidget {
  final Color seed;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const HeroHeader({
    super.key,
    required this.seed,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 20),
  });

  @override
  Widget build(BuildContext context) {
    final koyu = Color.lerp(seed, const Color(0xFF0F172A), 0.35)!;
    final acik = Color.lerp(seed, Colors.white, 0.08)!;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [acik, seed, koyu],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: koyu.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: Stack(
          children: [
            // Işıltı dokunuşları: login ekranındaki blob dilinin devamı.
            Positioned(
              top: -60,
              right: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.white.withValues(alpha: 0.18), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -70,
              left: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.black.withValues(alpha: 0.14), Colors.transparent],
                  ),
                ),
              ),
            ),
            SafeArea(bottom: false, child: Padding(padding: padding, child: child)),
          ],
        ),
      ),
    );
  }
}

/// Hero başlık içinde kullanılan cam (glass) istatistik kutusu.
class GlassStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  const GlassStat({super.key, required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Gradyanlı birincil buton: login'deki "GİRİŞ YAP" butonunun genel hali.
/// [seed] firma rengi; [danger]/[success] gibi özel durumlar için [colors] verilebilir.
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData? icon;
  final String label;
  final Color seed;
  final List<Color>? colors;
  final double height;
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.seed,
    this.icon,
    this.colors,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final grad = colors ?? AppTheme.brandGradient(seed).colors;
    final golge = grad.first;
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: onPressed == null
              ? [Colors.grey.shade400, Colors.grey.shade500]
              : grad,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: onPressed == null
            ? const []
            : [BoxShadow(color: golge.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Türkçe tarih başlığı ("28 Temmuz Salı" gibi) — intl bağımlılığı olmadan.
String turkceTarih(DateTime t) {
  const aylar = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];
  const gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
  return '${t.day} ${aylar[t.month - 1]} ${gunler[t.weekday - 1]}';
}
