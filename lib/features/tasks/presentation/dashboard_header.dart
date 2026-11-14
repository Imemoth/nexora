import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import 'strings/app_strings.dart';
import 'theme/nexora_colors.dart';

/// Metric cards above the task list: due today, overdue, in progress, and a
/// progress ring. Every number is computed from the tasks already loaded.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key, required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final colors = NexoraColors.of(context);
    final progress = state.progress;
    final fraction = progress.total == 0 ? 0.0 : progress.done / progress.total;
    final cards = <Widget>[
      _MetricCard(
        key: const ValueKey('metric-today'),
        label: AppStrings.metricDueToday,
        value: state.countFor(const SmartViewSelection(SmartView.today)),
        icon: Icons.today_outlined,
        color: colors.statusOpen,
      ),
      _MetricCard(
        key: const ValueKey('metric-overdue'),
        label: AppStrings.metricOverdue,
        value: state.countFor(const SmartViewSelection(SmartView.overdue)),
        icon: Icons.warning_amber_outlined,
        color: colors.statusOverdue,
      ),
      _MetricCard(
        key: const ValueKey('metric-progress-count'),
        label: AppStrings.metricInProgress,
        value: state.countWithStatus(TaskStatus.inProgress),
        icon: Icons.timelapse,
        color: colors.statusProgress,
      ),
      _ProgressCard(
        key: const ValueKey('metric-ring'),
        fraction: fraction,
        done: progress.done,
        total: progress.total,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = NexoraColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.tint(color),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(color: colors.text2),
                  ),
                  Text(
                    value.toString(),
                    style: textTheme.titleLarge?.copyWith(height: 1.1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    super.key,
    required this.fraction,
    required this.done,
    required this.total,
  });

  final double fraction;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = NexoraColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final percent = (fraction * 100).round();
    return Semantics(
      label: AppStrings.progressLabel(done, total),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: colors.selectedGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.borderStrong),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CustomPaint(
                  painter: _RingPainter(
                    fraction: fraction,
                    track: colors.border,
                    start: colors.accentCyan,
                    end: colors.accentViolet,
                  ),
                  child: Center(
                    child: Text(
                      '$percent%',
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.text1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppStrings.metricProgress,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(
                        color: colors.text1,
                      ),
                    ),
                    Text(
                      AppStrings.progressLabel(done, total),
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: colors.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.track,
    required this.start,
    required this.end,
  });

  final double fraction;
  final Color track;
  final Color start;
  final Color end;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base);
    if (fraction <= 0) {
      return;
    }
    final sweep = math.pi * 2 * fraction.clamp(0.0, 1.0);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + math.pi * 2,
        colors: [start, end],
        transform: const GradientRotation(0),
      ).createShader(rect);
    canvas.drawArc(arcRect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) {
    return old.fraction != fraction ||
        old.track != track ||
        old.start != start ||
        old.end != end;
  }
}
