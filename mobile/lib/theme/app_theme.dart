import 'package:flutter/material.dart';

/// Uygulama geneli tema ve yeniden kullanılabilir görsel yardımcılar.
class AppTheme {
  /// '#RRGGBB' hex kodunu güvenle Color'a çevirir. Sunucudan bozuk/eksik değer
  /// gelirse (örn. yönetici panele 'mavi' yazdıysa) çökmek yerine varsayılana döner.
  static Color parseHex(String? hex, {Color fallback = const Color(0xFF3B82F6)}) {
    if (hex == null) return fallback;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return fallback;
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  static const Color bg = Color(0xFFF1F5F9); // slate-100
  static const Color surface = Colors.white;
  static const Color textDark = Color(0xFF0F172A); // slate-900
  static const Color textMuted = Color(0xFF64748B); // slate-500
  static const Color fieldFill = Color(0xFFF8FAFC); // slate-50
  static const Color border = Color(0xFFE2E8F0); // slate-200

  // Anlamsal (semantic) renkler — durum butonları/ikonları için tutarlı palet.
  static const Color success = Color(0xFF16A34A); // green-600
  static const Color danger = Color(0xFFDC2626);  // red-600
  static const Color warning = Color(0xFFD97706); // amber-600
  static const Color info = Color(0xFF7C3AED);    // violet-600

  // Kartlar için tek noktadan gölge (Premium, katmanlı, çok yumuşak gölge).
  static List<BoxShadow> get cardShadow => [
        BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 12)),
      ];

  // Standart kart kutusu süslemesi (beyaz + 20 köşe + premium gölge).
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: cardShadow,
      );

  /// Liste boşken gösterilecek tutarlı boş durum: ikon + başlık + açıklama.
  /// RefreshIndicator ile çalışması için kaydırılabilir bir gövde döndürür.
  static Widget emptyState({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? accent,
  }) {
    final c = accent ?? textMuted;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: c.withValues(alpha: 0.10), shape: BoxShape.circle),
                child: Icon(icon, size: 40, color: c),
              ),
              const SizedBox(height: 18),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textDark)),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: textMuted, height: 1.4)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Renkli bilgi/uyarı paneli (ekranlarda tekrar eden inline panellerin yerine).
  static Widget infoPanel({
    required IconData icon,
    required Color color,
    required String text,
    String? title,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 3),
                ],
                Text(text, style: const TextStyle(color: textDark, fontSize: 13, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tutarlı yükleme göstergesi (ekran içi loading durumları için).
  static Widget loadingBox(String text, {Color? color}) {
    final c = color ?? textMuted;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3, color: c)),
          const SizedBox(height: 14),
          Text(text, style: const TextStyle(color: textMuted, fontSize: 13.5)),
        ],
      ),
    );
  }

  /// Form/detay bölüm başlığı (büyük harf, seyrek izli, soluk).
  static Widget sectionLabel(String text, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[Icon(icon, size: 15, color: textMuted), const SizedBox(width: 6)],
        Text(
          text.toUpperCase(),
          style: const TextStyle(color: textMuted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
        ),
      ],
    );
  }

  static ThemeData build(Color seed) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);

    OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: seed,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: surface,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          shadowColor: seed.withValues(alpha: 0.4),
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.3), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w400),
        border: ob(border),
        enabledBorder: ob(border),
        focusedBorder: ob(seed, 2.0),
        errorBorder: ob(danger, 1.5),
      ),
      cardColor: surface,
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: fieldFill,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: ob(border),
          enabledBorder: ob(border),
          focusedBorder: ob(seed, 1.6),
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontWeight: FontWeight.bold, color: textDark),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, color: textDark),
        titleSmall: TextStyle(fontWeight: FontWeight.w600, color: textDark, fontSize: 14),
        bodyLarge: TextStyle(color: textDark, fontSize: 15, height: 1.4),
        bodyMedium: TextStyle(color: textDark, fontSize: 13.5, height: 1.4),
        labelLarge: TextStyle(fontWeight: FontWeight.w600, color: textDark),
      ),
    );
  }
}

/// Durum (status) görselleştirme yardımcıları.
class StatusUi {
  // (arka plan, metin rengi, etiket)
  static (Color, Color, String) style(String? durum) {
    switch (durum) {
      case 'tamamlandi':
        return (const Color(0xFFDCFCE7), const Color(0xFF15803D), 'Tamamlandı');
      case 'devam_ediyor':
        return (const Color(0xFFFEF3C7), const Color(0xFFB45309), 'Devam Ediyor');
      case 'bekliyor':
        return (const Color(0xFFF1F5F9), const Color(0xFF475569), 'Bekliyor');
      case 'iptal':
        return (const Color(0xFFFEE2E2), const Color(0xFFB91C1C), 'İptal');
      case 'acik':
        return (const Color(0xFFFEE2E2), const Color(0xFFB91C1C), 'Açık');
      case 'cozuldu':
        return (const Color(0xFFDCFCE7), const Color(0xFF15803D), 'Çözüldü');
      case 'dis_destek':
        return (const Color(0xFFF3E8FF), const Color(0xFF7E22CE), 'Dış Destek');
      case 'onaylandi':
        return (const Color(0xFFDCFCE7), const Color(0xFF15803D), 'Onaylandı');
      case 'reddedildi':
        return (const Color(0xFFFEE2E2), const Color(0xFFB91C1C), 'Reddedildi');
      default:
        return (const Color(0xFFF1F5F9), const Color(0xFF475569), (durum ?? '-').toUpperCase());
    }
  }

  // Duruma karşılık gelen ikon (renk körü dostu ek ipucu).
  static IconData icon(String? durum) {
    switch (durum) {
      case 'tamamlandi':
      case 'cozuldu':
      case 'onaylandi':
        return Icons.check_circle;
      case 'devam_ediyor':
        return Icons.autorenew;
      case 'bekliyor':
        return Icons.schedule;
      case 'iptal':
      case 'reddedildi':
        return Icons.cancel;
      case 'acik':
        return Icons.error_outline;
      case 'dis_destek':
        return Icons.engineering;
      default:
        return Icons.circle;
    }
  }

  static Widget chip(String? durum) {
    final (bg, fg, label) = style(durum);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon(durum), size: 13, color: fg),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
