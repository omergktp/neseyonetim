import 'package:flutter/material.dart';
import '../main.dart'; // To access scaffoldMessengerKey

class UiUtils {
  static void showSnackBar(String message, {bool isError = false}) {
    final state = scaffoldMessengerKey.currentState;
    if (state != null) {
      state.hideCurrentSnackBar();
      state.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
