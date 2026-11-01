import 'dart:async';

import 'package:flutter/services.dart';

/// Android sends encoder movement as logical pixels, independent of touch focus.
class RotaryInput {
  static const channel = MethodChannel('life_assistant/rotary');
  static final _events = StreamController<double>.broadcast(sync: true);
  static bool _initialized = false;

  static Stream<double> get events {
    if (!_initialized) {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'scroll' && call.arguments is num) {
          final delta = (call.arguments as num).toDouble();
          if (delta.isFinite && delta != 0) _events.add(delta);
        }
      });
      _initialized = true;
    }
    return _events.stream;
  }
}
