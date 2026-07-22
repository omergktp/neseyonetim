import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// GLOW SAHA marka logosu — TEK reçete (login, splash ve web ile aynı):
/// gradyan #3B82F6 → #8B5CF6, köşe = genişliğin %26'sı, mor gölge.
/// Logoyu başka yerde elle çizme; her zaman bu widget'ı kullan.
class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 84});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'G',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: size * 0.52,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
