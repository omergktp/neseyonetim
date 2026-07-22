import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart'; // To access scaffoldMessengerKey

/// Bildirime tıklayınca ekran açabilmek için global navigator anahtarı.
/// main.dart'ta MaterialApp'e verilir; FcmService yönlendirme için kullanır.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class UiUtils {
  /// Mesaj gösterir. Eldivenli/aceleci saha kullanımı için dokunsal geri bildirim
  /// de verir: hata = güçlü titreşim, bilgi = hafif titreşim.
  static void showSnackBar(String message,
      {bool isError = false, String? actionLabel, VoidCallback? onAction}) {
    if (isError) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    final state = scaffoldMessengerKey.currentState;
    if (state != null) {
      state.hideCurrentSnackBar();
      state.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: actionLabel != null ? 6 : 4),
          action: actionLabel != null
              ? SnackBarAction(
                  label: actionLabel,
                  textColor: Colors.white,
                  onPressed: onAction ?? () {},
                )
              : null,
        ),
      );
    }
  }
}
