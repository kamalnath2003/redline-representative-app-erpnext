import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The RCD Sales brand mark (`assets/RCD_logo.svg`).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
        'assets/RCD_logo.svg',
      width: size,
      height: size,
        fit: BoxFit.contain,
    );
  }
}
