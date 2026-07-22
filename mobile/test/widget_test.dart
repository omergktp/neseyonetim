// Glow Saha temel smoke test'i.
// Uygulamanın hatasız kurulup açılış (Splash) ekranını çizebildiğini doğrular.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glow_saha/main.dart';

void main() {
  testWidgets('Uygulama açılışta hatasız kurulur', (WidgetTester tester) async {
    // MyApp yeni imzasıyla (tema rengi zorunlu) kurulur.
    await tester.pumpWidget(const MyApp(themeColorHex: '#3B82F6'));

    // İlk kare çizilir; widget ağacında MaterialApp bulunmalı.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
