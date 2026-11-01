import 'package:flutter/services.dart';

abstract class FocusEngine {
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? arguments,
  ]);
}

class AndroidFocusEngine implements FocusEngine {
  static const channel = MethodChannel('life_assistant/focus');
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      method,
      arguments,
    );
    return Map<String, dynamic>.from(result ?? {});
  }
}
