import 'package:flutter/services.dart';

class HapticService {
  static void light() => HapticFeedback.selectionClick();
  static void medium() => HapticFeedback.mediumImpact();
  static void heavy() => HapticFeedback.heavyImpact();
  static void success() => HapticFeedback.vibrate();
}
