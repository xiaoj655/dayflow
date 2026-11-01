import 'package:flutter/widgets.dart';

/// Shares the controller's clock with time-sensitive UI (and documentation).
class AppClock extends InheritedWidget {
  const AppClock({super.key, required this.clock, required super.child});

  final DateTime Function() clock;

  static DateTime now(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppClock>()?.clock() ??
      DateTime.now();

  @override
  bool updateShouldNotify(AppClock oldWidget) => clock != oldWidget.clock;
}
