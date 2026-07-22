import 'package:flutter/material.dart';

class GlowingBlob extends StatelessWidget {
  final Color color;
  final double size;

  const GlowingBlob({
    Key? key,
    required this.color,
    this.size = 220,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.45),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}
