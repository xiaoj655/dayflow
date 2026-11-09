import 'package:flutter/material.dart';

/// Neutral surfaces with red primary actions and selected states.
abstract final class AppColors {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF161616);
  static const overlay = Color(0xFF262626);
  static const faint = Color(0xFF888888);
  static const primary = Color(0xFFFF2056);
  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0xFFC5C5C5);
  static const focus = primary;
  static const error = focus;

  // Data colors are confined to the analysis timeline.
  static const timelineLife = Color(0xFFFF8AAE);
  static const timelineWork = Color(0xFFB18AFF);
  static const timelineRest = Color(0xFF60E8AF);
}
