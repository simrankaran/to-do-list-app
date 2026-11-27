import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/todo_store.dart';

/// Streaks, completion rate and a 7-day completions chart.
class StatsSection extends StatelessWidget {
  const StatsSection({super.key, required this.store});
  final TodoStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topLevel = store.tasks.where((t) => !t.isSubtask).toList();
    final done = topLevel.where((t) => t.done).length;
    final rate = topLevel.isEmpty ? 0.0 : done / topLevel.length;
    final streak = store.currentStreak;
    final best = store.bestStreak;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your progress', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Tile(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: const Color(0xFFF97316),
                  value: '$streak',
                  label: 'day streak',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  icon: Icons.emoji_events_rounded,
                  iconColor: const Color(0xFFEAB308),
                  value: '$best',
                  label: 'best streak',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  ring: rate,
                  value: '${(rate * 100).round()}%',
                  label: 'completed',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Completed · last 7 days',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 12),
                _WeekChart(store: store),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
    this.ring,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? iconColor;

  /// When set, shows a progress ring (0–1) instead of an icon.
  final double? ring;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 32,
            child: ring != null
                ? TweenAnimationBuilder<double>(
                    tween: Tween(end: ring),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      color: scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  )
                : Icon(icon, size: 30, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Seven thin bars, one per day, anchored to a shared baseline. Each bar has
/// a tooltip (tap and hold) with the exact count.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.store});
  final TodoStore store;

  static const double _plotHeight = 96;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = store.recentCompletions(7);
    final maxCount = days.fold<int>(0, (m, d) => math.max(m, d.count));
    final total = days.fold<int>(0, (s, d) => s + d.count);

    return Semantics(
      label:
          'Tasks completed in the last 7 days: ${days.map((d) => '${DateFormat.E().format(d.day)} ${d.count}').join(', ')}. Total $total.',
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(
            height: _plotHeight + 18,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, d) in days.indexed)
                  Expanded(
                    child: Padding(
                      // 2px surface gap between neighbouring bars.
                      padding: EdgeInsets.only(
                        left: i == 0 ? 0 : 1,
                        right: i == 6 ? 0 : 1,
                      ),
                      child: Tooltip(
                        message:
                            '${DateFormat('EEE d MMM').format(d.day)} · ${d.count} done',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Label only the best day and today, not every bar.
                            if (d.count > 0 &&
                                (d.count == maxCount || i == days.length - 1))
                              Text(
                                '${d.count}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  letterSpacing: 0,
                                  color: scheme.onSurface,
                                ),
                              ),
                            const SizedBox(height: 2),
                            Center(
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(
                                  end: maxCount == 0 ? 0 : d.count / maxCount,
                                ),
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeOutCubic,
                                builder: (context, v, _) => Container(
                                  width: 18,
                                  height: math.max(
                                    v * _plotHeight,
                                    d.count > 0 ? 4 : 0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: i == days.length - 1
                                        ? scheme.primary
                                        : scheme.primary.withValues(
                                            alpha: 0.45,
                                          ),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
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
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (i, d) in days.indexed)
                Expanded(
                  child: Text(
                    DateFormat.E().format(d.day).substring(0, 1),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0,
                      fontWeight: i == days.length - 1
                          ? FontWeight.w800
                          : FontWeight.w400,
                      color: i == days.length - 1
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          if (total == 0) ...[
            const SizedBox(height: 8),
            Text(
              'Complete a task to start your streak.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
