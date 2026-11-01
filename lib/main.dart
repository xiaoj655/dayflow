import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controllers/app_controller.dart';
import 'data/local_store.dart';
import 'data/mysql_repository.dart';
import 'pages/app_pages.dart';
import 'platform/focus_engine.dart';
import 'widgets/screen_viewport.dart';
import 'widgets/app_clock.dart';

const deviceChannel = MethodChannel('life_assistant/device');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var isRound = false;
  try {
    isRound = await deviceChannel.invokeMethod<bool>('isScreenRound') ?? false;
  } on MissingPluginException {
    /* Native desktop tooling uses rectangular pages. */
  } on PlatformException {
    /* A missing shape hint must not prevent launch. */
  }
  if (isRound) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  final controller = AppController(
    repository: await MySqlTaskRepository.load(),
    store: PreferenceStore(),
    engine: AndroidFocusEngine(),
  );
  runApp(
    MyApp(controller: controller, isRound: isRound, initializeController: true),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.controller,
    this.isRound = false,
    this.initializeController = false,
  });
  final AppController controller;
  final bool isRound;
  final bool initializeController;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Timer? _ticker;
  int _seconds = 0;
  late String _today;
  late bool _ready;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _today = widget.controller.today;
    _ready = !widget.initializeController;
    if (_ready) {
      unawaited(widget.controller.refresh());
      _startTicker();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_initialize());
      });
    }
  }

  Future<void> _initialize() async {
    try {
      await widget.controller.initialize();
    } catch (error) {
      debugPrint('Local restore failed: ${error.runtimeType}');
    }
    if (!mounted) return;
    _ready = true;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _startTicker();
    }
    unawaited(widget.controller.refresh());
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.controller.focus?.running == true) {
        unawaited(widget.controller.refreshFocus());
      }
      final today = widget.controller.today;
      if (today != _today) {
        if (widget.controller.date == _today) {
          unawaited(widget.controller.selectDate(DateTime.parse(today)));
        }
        _today = today;
      }
      if (++_seconds % 30 == 0) unawaited(widget.controller.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ready) return;
    if (state == AppLifecycleState.resumed) {
      _startTicker();
      unawaited(widget.controller.refreshFocus());
      unawaited(widget.controller.refresh());
    } else {
      _ticker?.cancel();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Dayflow',
    builder: (context, child) => AppClock(
      clock: widget.controller.clock,
      child: ScreenShape(isRound: widget.isRound, child: child!),
    ),
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: Color(0xFF181014),
        surface: surface,
        secondary: accent,
        onSecondary: Color(0xFF181014),
      ),
      platform: TargetPlatform.android,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
        ),
        titleMedium: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontSize: 16, height: 1.4),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          side: BorderSide.none,
          backgroundColor: surface,
          foregroundColor: Colors.white,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    ),
    home: TaskListPage(controller: widget.controller, isRound: widget.isRound),
  );
}
