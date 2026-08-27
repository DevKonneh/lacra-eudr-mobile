import 'package:flutter/material.dart';

/// Reusable LACRA brand mark. Renders the bundled logo image inside a
/// circular white badge with a soft shadow so it reads well on both light
/// backgrounds and the green hero gradients used across auth screens.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72, this.padding = 10});

  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/lacra_logo.jpg',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.eco,
            color: Color(0xFF2E7D32),
          ),
        ),
      ),
    );
  }
}
