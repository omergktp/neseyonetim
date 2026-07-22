import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glow_saha/theme/app_theme.dart';

void main() {
  group('AppTheme.parseHex', () {
    const varsayilan = Color(0xFF3B82F6);

    test('#RRGGBB doğru çözülür', () {
      expect(AppTheme.parseHex('#16A34A'), const Color(0xFF16A34A));
      expect(AppTheme.parseHex('DC2626'), const Color(0xFFDC2626)); // # işaretsiz de olur
    });

    test('bozuk değerler çökmek yerine varsayılana döner', () {
      expect(AppTheme.parseHex('mavi'), varsayilan);
      expect(AppTheme.parseHex('#3B82F'), varsayilan);   // 5 hane
      expect(AppTheme.parseHex(''), varsayilan);
      expect(AppTheme.parseHex(null), varsayilan);
      expect(AppTheme.parseHex('#GGGGGG'), varsayilan);  // hex olmayan karakter
    });
  });

  group('StatusUi', () {
    test('bilinen durumlar etiketlenir, bilinmeyen düşmez', () {
      expect(StatusUi.style('tamamlandi').$3, 'Tamamlandı');
      expect(StatusUi.style('dis_destek').$3, 'Dış Destek');
      expect(StatusUi.style('garip_durum').$3, 'GARIP_DURUM');
      expect(StatusUi.style(null).$3, '-');
    });
  });
}
