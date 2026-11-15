import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_colors.dart';
import '../controllers/app_controller.dart';
import '../models/focus_session.dart';

/// Opens the full timer and keeps its frequent pause action on the task list.
class HomeFocusCard extends StatefulWidget {
  const HomeFocusCard({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onError,
  });

  final AppController controller;
  final VoidCallback onOpen;
  final ValueChanged<String> onError;

  @override
  State<HomeFocusCard> createState() => _HomeFocusCardState();
}

class _HomeFocusCardState extends State<HomeFocusCard> {
  bool busy = false;
  bool get isCurrent => mounted && ModalRoute.of(context)?.isCurrent == true;

  bool _unchanged(AppController controller, FocusSession session) =>
      isCurrent &&
      identical(widget.controller, controller) &&
      controller.focus?.id == session.id &&
      controller.focus?.status == session.status &&
      controller.focus?.active == true;

  Future<void> _toggle() async {
    final controller = widget.controller;
    final session = controller.focus;
    if (busy || !isCurrent || session == null || !session.active) return;
    setState(() => busy = true);
    try {
      if (session.paused && session.kind == 'focus') {
        await controller.engine.call('permissions');
        if (!_unchanged(controller, session)) return;
        // Permission screens can remain open while the native timer changes.
        await controller.refreshFocus();
        if (!_unchanged(controller, session)) return;
      }
      await controller.focusAction(session.paused ? 'resume' : 'pause');
    } on PlatformException catch (error) {
      if (isCurrent) widget.onError(error.message ?? '暂时无法更改计时状态，请重试');
    } catch (_) {
      if (isCurrent) widget.onError('暂时无法更改计时状态，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _timer(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final session = widget.controller.focus;
      if (session == null || !session.active) return const SizedBox.shrink();
      final rest = session.kind == 'rest';
      final focusing = !session.paused && !rest;
      final state = session.paused ? '已暂停' : (rest ? '休息中' : '专注中');
      final action = '${session.paused ? '继续' : '暂停'}${rest ? '休息' : '专注'}';
      final timer = _timer(session.remainingSeconds);
      void open() {
        if (isCurrent) widget.onOpen();
      }

      return Material(
        key: const ValueKey('home-focus-card'),
        color: AppColors.surface,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.outline)),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                key: const ValueKey('home-focus-open'),
                button: true,
                label: '返回专注，${session.taskTitle}，$state，剩余 $timer',
                onTap: open,
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: open,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 12,
                                  color: focusing
                                      ? AppColors.focus
                                      : AppColors.muted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  state,
                                  style: TextStyle(
                                    color: focusing
                                        ? AppColors.focus
                                        : AppColors.muted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  timer,
                                  style: TextStyle(
                                    color: session.paused
                                        ? AppColors.muted
                                        : AppColors.text,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -.4,
                                    height: 1,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            session.taskTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                key: const ValueKey('home-focus-toggle'),
                tooltip: action,
                onPressed: busy ? null : _toggle,
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  maximumSize: const Size(40, 40),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: AppColors.overlay,
                  foregroundColor: AppColors.text,
                  disabledBackgroundColor: AppColors.overlay,
                  disabledForegroundColor: AppColors.faint,
                ),
                icon: Icon(
                  session.paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
