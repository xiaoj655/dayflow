import 'package:flutter/material.dart';

import '../app_colors.dart';

/// Frequent timer actions keep their full touch area on a round display.
class ActiveFocusControls extends StatelessWidget {
  const ActiveFocusControls({
    super.key,
    required this.paused,
    required this.isRest,
    required this.busy,
    required this.onPauseResume,
    required this.onStop,
    this.compact = false,
  });

  final bool paused, isRest, busy, compact;
  final VoidCallback onPauseResume, onStop;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 40.0 : 44.0;
    final width = compact ? 120.0 : 136.0;
    final primary = !paused && !isRest;
    final label = paused ? '继续' : '暂停';
    return SizedBox(
      key: const ValueKey('active-focus-controls'),
      width: width,
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconButton.filledTonal(
            key: const ValueKey('active-focus-stop'),
            tooltip: isRest ? '结束休息' : '提前结束',
            onPressed: busy ? null : onStop,
            constraints: BoxConstraints.tight(Size.square(height)),
            style: IconButton.styleFrom(
              fixedSize: Size.square(height),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.muted,
              disabledBackgroundColor: AppColors.surface,
              disabledForegroundColor: AppColors.faint,
            ),
            icon: const Icon(Icons.stop_rounded, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: label,
              child: FilledButton(
                key: const ValueKey('active-focus-toggle'),
                onPressed: busy ? null : onPauseResume,
                style: FilledButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: primary
                      ? AppColors.primary
                      : AppColors.overlay,
                  foregroundColor: primary
                      ? AppColors.background
                      : AppColors.text,
                  disabledBackgroundColor: AppColors.overlay,
                  disabledForegroundColor: AppColors.faint,
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 18,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          style: const TextStyle(fontSize: 13, height: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
