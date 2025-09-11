import 'package:flutter/widgets.dart';

/// Scales a base font size according to screen width with clamped factor.
/// Baseline width is 375 (common mobile width). Clamps between 0.8x and 1.3x.
double sf(BuildContext context, double base) {
  final w = MediaQuery.of(context).size.width;
  double factor = w / 375.0;
  if (factor < 0.8) factor = 0.8;
  if (factor > 1.3) factor = 1.3;
  return base * factor;
}

/// Scales general dimensions (icons, paddings, radii) according to screen width.
/// Uses the same baseline and clamps as sf for consistency.
double sd(BuildContext context, double base) {
  final w = MediaQuery.of(context).size.width;
  double factor = w / 375.0;
  if (factor < 0.8) factor = 0.8;
  if (factor > 1.3) factor = 1.3;
  return base * factor;
}

/// Scales spacing values (padding, margin, gaps) with the same curve as sf/sd.
/// Use this for SizedBox, EdgeInsets, and general layout gaps.
double sp(BuildContext context, double base) {
  final w = MediaQuery.of(context).size.width;
  double factor = w / 375.0;

  if (factor < 0.8) factor = 0.8;
  if (factor > 1.3) factor = 1.3;
  return base * factor;
}

// Common spacing presets
double gapS(BuildContext context) => sp(context, 8);
double gapM(BuildContext context) => sp(context, 16);
double gapL(BuildContext context) => sp(context, 24);

/// Scales values according to screen HEIGHT with a clamped factor.
/// Useful for vertical sizes like panel heights, charts, or vertical spacers.
/// Baseline height is 812 (common modern mobile height). Clamps between 0.8x and 1.3x.
double sh(BuildContext context, double base) {
  final h = MediaQuery.of(context).size.height;
  double factor = h / 812.0;
  if (factor < 0.8) factor = 0.8;
  if (factor > 1.3) factor = 1.3;
  return base * factor;
}
