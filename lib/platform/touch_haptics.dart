import 'package:flutter/services.dart';

/// The watch's standard selectionClick preset incorrectly lasts about 10 seconds.
/// Native code checks primitive support, system settings and rate limits ticks.
class TouchHaptics {
  static const channel = MethodChannel('life_assistant/haptics');
  static final _rotaryCadences = Expando<RotaryHapticCadence>();

  static Future<void> selectionClick() => _play('selection');

  /// Use the watch's native rotary feedback, independently of click feedback.
  static Future<void> rotaryScroll(
    double delta, {
    required Object source,
  }) async {
    final cadence = _rotaryCadences[source] ??= RotaryHapticCadence();
    if (cadence.advance(delta)) await _play('rotary');
  }

  static Future<void> _play(String method) async {
    try {
      await channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No haptics is preferable to the device's broken fallback preset.
    } on PlatformException {
      // Feedback must not prevent completing a task or editing a duration.
    }
  }
}

/// Spaced crown detents, resetting accumulated rotation on reversal.
class RotaryHapticCadence {
  // Read on this watch: system scroll factor 152px, encoder resolution -0.75056446.
  // Keep the app factor aligned with MainActivity's density clamp and speed.
  static const _degreesPerLogicalPixel = 152 / 0.75056446 / (32 * 2.04);
  static const _tickDegrees = 72;
  double _rotation = 0;
  double _direction = 0;

  bool advance(double delta) {
    if (!delta.isFinite || delta == 0) return false;
    if (delta.sign != _direction) _rotation = 0;
    _direction = delta.sign;
    _rotation += delta.abs() * _degreesPerLogicalPixel;
    if (_rotation < _tickDegrees) return false;
    // One pulse per input event; never queue a burst to catch up after a fast turn.
    _rotation %= _tickDegrees;
    return true;
  }
}
