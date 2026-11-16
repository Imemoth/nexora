import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/focus_ring.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/reminder_service.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/reminder_strip.dart';
import 'package:nexora/features/tasks/presentation/reminders_notifier.dart';
import 'package:nexora/features/tasks/presentation/status_badge.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/strings/reminder_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

import 'account_panel.dart';
import 'conflict_panel.dart';
import 'project_tile.dart';
import 'sync_card.dart';
import 'sync_panel.dart';
import 'sync_presentation.dart';

/// Read-only overview of the workspace. It reads existing state only; it
/// writes nothing except through the same reminder and sync actions as the rest
/// of the app.
class DashboardPane extends StatelessWidget {
  const DashboardPane({
    super.key,
    this.syncPanel,
    this.accountPanel,
    this.conflictPanel,
  });

  final SyncPanel? syncPanel;
  final AccountPanel? accountPanel;
  final ConflictPanel? conflictPanel;

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;
    final c = NexoraColors.of(context);
    return ListView(
      key: const ValueKey('dashboard-pane'),
      children: [
        Text(
          AppStrings.friendlyDate(state.today),
          style: NexoraText.caption.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          AppStrings.dashboardTitle,
          style: NexoraText.titlePage.copyWith(color: c.text1),
        ),
        const SizedBox(height: 16),
        _StatTiles(notifier: notifier, state: state),
        const SizedBox(height: 16),
        _RemindersCard(notifier: notifier),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final needs = _NeedsAttention(notifier: notifier, state: state);
            final right = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SyncPanelCard(
                  syncPanel: syncPanel,
                  accountPanel: accountPanel,
                  conflictPanel: conflictPanel,
                ),
                const SizedBox(height: 16),
                _ProjectsCard(notifier: notifier, state: state),
              ],
            );
            if (constraints.maxWidth < 624) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [needs, const SizedBox(height: 16), right],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: needs),
                const SizedBox(width: 16),
                Expanded(child: right),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.child, this.border});

  final Widget child;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border ?? c.border),
      ),
      child: child,
    );
  }
}

class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.notifier, required this.state});

  final TasksNotifier notifier;
  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final tiles = [
      (SmartView.today, AppStrings.dashNoteToday, c.accentCyan),
      (SmartView.overdue, AppStrings.dashNoteOverdue, c.statusOverdue),
      (SmartView.next7Days, AppStrings.dashNoteNext7, c.text1),
      (SmartView.all, AppStrings.dashNoteAll, c.text1),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + 12) / (150 + 12))
            .floor()
            .clamp(1, 4);
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (view, note, color) in tiles)
              SizedBox(
                width: width,
                child: _StatTile(
                  key: ValueKey('dash-tile-${view.name}'),
                  label: AppStrings.smartViewLabel(view),
                  note: note,
                  count: state.countFor(SmartViewSelection(view)),
                  color: color,
                  onTap: () => notifier.selectView(view),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.note,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String note;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return Semantics(
      button: true,
      label: '$label, $count, $note',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.border),
        ),
        child: FocusRing(
          radius: 10,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            hoverColor: c.surface2,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: NexoraText.caption.copyWith(color: c.text2),
                  ),
                  Text(
                    count.toString(),
                    key: ValueKey('dash-count-$label'),
                    style: NexoraText.displayStat.copyWith(color: color),
                  ),
                  Text(
                    note,
                    style: NexoraText.caption.copyWith(color: c.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RemindersCard extends StatelessWidget {
  const _RemindersCard({required this.notifier});

  final TasksNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final reminders = ReminderScope.maybeOf(context);
    if (reminders == null) {
      return const SizedBox.shrink();
    }
    final c = NexoraColors.of(context);
    final service = reminders.service;
    final due = service.due;
    final scheduled = service.scheduled;
    return _Card(
      key: const ValueKey('dashboard-reminders'),
      border: due.isEmpty ? null : c.accentCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_none, size: 18, color: c.accentCyan),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${ReminderStrings.bannerTitle} · '
                  '${ReminderStrings.summary(due.length, scheduled.length)}',
                  style: NexoraText.bodyStrong.copyWith(color: c.text1),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ReminderStrings.deviceTag,
                  style: NexoraText.label.copyWith(color: c.text2),
                ),
              ),
              const Spacer(),
              if (due.isNotEmpty)
                TextButton(
                  key: const ValueKey('reminder-dismiss-all'),
                  onPressed: () {
                    for (final item in due) {
                      service.acknowledge(item.taskId);
                    }
                  },
                  child: const Text(ReminderStrings.dismissAll),
                ),
            ],
          ),
          if (!reminders.nativeAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                ReminderStrings.nativeUnavailable,
                style: NexoraText.caption.copyWith(color: c.textMuted),
              ),
            ),
          if (due.isEmpty && scheduled.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                ReminderStrings.noRemindersDue,
                style: NexoraText.body.copyWith(color: c.text2),
              ),
            ),
          for (final item in due)
            _DueRow(item: item, service: service, notifier: notifier),
          for (final item in scheduled)
            _ScheduledRow(item: item, service: service, notifier: notifier),
        ],
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({
    required this.item,
    required this.service,
    required this.notifier,
  });

  final DueReminder item;
  final ReminderService service;
  final TasksNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        key: ValueKey('dash-reminder-${item.taskId}'),
        children: [
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexoraText.bodyStrong.copyWith(color: c.text1),
            ),
          ),
          Text(
            item.missed
                ? '${ReminderStrings.state(item.reminder)} · '
                      '${ReminderStrings.missedTag}'
                : ReminderStrings.state(item.reminder),
            style: NexoraText.label.copyWith(
              color: item.missed ? c.statusOverdue : c.text2,
            ),
          ),
          TextButton(
            key: ValueKey('dash-open-${item.taskId}'),
            onPressed: () => notifier.revealTask(item.taskId),
            child: const Text(ReminderStrings.openTask),
          ),
          SnoozeMenuButton(
            buttonKey: ValueKey('dash-snooze-${item.taskId}'),
            taskId: item.taskId,
            service: service,
          ),
          FilledButton(
            key: ValueKey('dash-done-${item.taskId}'),
            onPressed: () => service.acknowledge(item.taskId),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text(ReminderStrings.acknowledge),
          ),
        ],
      ),
    );
  }
}

class _ScheduledRow extends StatelessWidget {
  const _ScheduledRow({
    required this.item,
    required this.service,
    required this.notifier,
  });

  final DueReminder item;
  final ReminderService service;
  final TasksNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final reminder = item.reminder;
    final when = reminder.snoozeUntilUtc == null
        ? reminder.remindAt
        : service.clock.toLocal(reminder.snoozeUntilUtc!);
    return FocusRing(
      radius: 10,
      child: InkWell(
        key: ValueKey('dash-scheduled-${item.taskId}'),
        borderRadius: BorderRadius.circular(8),
        hoverColor: c.surface2,
        onTap: () => notifier.revealTask(item.taskId),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexoraText.body.copyWith(color: c.text1),
                ),
              ),
              Text(
                '${ReminderStrings.friendlyWhen(when)} · '
                '${ReminderStrings.state(reminder)}',
                style: NexoraText.label.copyWith(color: c.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({required this.notifier, required this.state});

  final TasksNotifier notifier;
  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final today = state.today;
    final tasks =
        [
          for (final task in state.tasks.values)
            if (_needsAttention(task, today)) task,
        ]..sort((a, b) {
          final byDue = a.dueDate!.compareTo(b.dueDate!);
          return byDue != 0 ? byDue : a.id.compareTo(b.id);
        });
    return _Card(
      key: const ValueKey('dashboard-attention'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.needsAttention,
            style: NexoraText.bodyStrong.copyWith(color: c.text1),
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            Text(
              AppStrings.nothingDue,
              style: NexoraText.body.copyWith(color: c.text2),
            ),
          for (final task in tasks)
            FocusRing(
              radius: 10,
              child: InkWell(
                key: ValueKey('attention-${task.id}'),
                borderRadius: BorderRadius.circular(8),
                hoverColor: c.surface2,
                onTap: () => notifier.revealTask(task.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      StatusRing(status: task.status),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NexoraText.bodyStrong.copyWith(color: c.text1),
                        ),
                      ),
                      Text(
                        AppStrings.friendlyDue(
                          task.dueDate!,
                          today,
                          closed: false,
                        ),
                        style: NexoraText.label.copyWith(
                          color: task.dueDate!.compareTo(today) < 0
                              ? c.statusOverdue
                              : c.accentCyan,
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

  /// Overdue and due-today tasks that are still open, oldest first.
  bool _needsAttention(Task task, CalendarDate today) {
    final due = task.dueDate;
    if (due == null ||
        task.status == TaskStatus.done ||
        task.status == TaskStatus.archived) {
      return false;
    }
    return due.compareTo(today) <= 0;
  }
}

class _SyncPanelCard extends StatelessWidget {
  const _SyncPanelCard({
    required this.syncPanel,
    required this.accountPanel,
    required this.conflictPanel,
  });

  final SyncPanel? syncPanel;
  final AccountPanel? accountPanel;
  final ConflictPanel? conflictPanel;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return PanelStreams(
      syncPanel: syncPanel,
      accountPanel: accountPanel,
      builder: (context, values) {
        final presentation = describeSync(
          values.status,
          signedIn: isSignedIn(accountPanel, values.account),
        );
        final handler = syncActionHandler(
          context,
          presentation: presentation,
          status: values.status,
          syncPanel: syncPanel,
          accountPanel: accountPanel,
          conflictPanel: conflictPanel,
        );
        return _Card(
          key: const ValueKey('dashboard-sync'),
          border: syncBorderColor(c, presentation.border),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.synchronizationHeader,
                style: NexoraText.bodyStrong.copyWith(color: c.text1),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      presentation.title,
                      key: const ValueKey('dash-sync-title'),
                      style: NexoraText.bodyStrong.copyWith(color: c.text1),
                    ),
                  ),
                  if (handler != null)
                    TextButton(
                      key: ValueKey(
                        'dash-${syncActionKeyName(presentation.action)}',
                      ),
                      onPressed: handler,
                      child: Text(syncActionLabel(presentation.action)),
                    ),
                ],
              ),
              if (presentation.sentence.isNotEmpty)
                Text(
                  presentation.sentence,
                  style: NexoraText.caption.copyWith(color: c.text2),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ProjectsCard extends StatelessWidget {
  const _ProjectsCard({required this.notifier, required this.state});

  final TasksNotifier notifier;
  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return _Card(
      key: const ValueKey('dashboard-projects'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.projectsHeader,
            style: NexoraText.bodyStrong.copyWith(color: c.text1),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < state.projects.length; i++)
            _ProjectRow(notifier: notifier, state: state, index: i, colors: c),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.notifier,
    required this.state,
    required this.index,
    required this.colors,
  });

  final TasksNotifier notifier;
  final WorkspaceState state;
  final int index;
  final NexoraColors colors;

  @override
  Widget build(BuildContext context) {
    final project = state.projects[index];
    final tasks = state.tasks.values.where((t) => t.projectId == project.id);
    final total = tasks.length;
    final done = tasks.where((t) => t.status == TaskStatus.done).length;
    final fraction = total == 0 ? 0.0 : done / total;
    return FocusRing(
      radius: 10,
      child: InkWell(
        key: ValueKey('dash-project-${project.id}'),
        borderRadius: BorderRadius.circular(8),
        hoverColor: colors.surface2,
        onTap: () => notifier.selectProject(project.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: projectDotColor(colors, index),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      project.name,
                      overflow: TextOverflow.ellipsis,
                      style: NexoraText.bodyStrong.copyWith(
                        color: colors.text1,
                      ),
                    ),
                  ),
                  Text(
                    AppStrings.projectProgress(done, total),
                    style: NexoraText.label.copyWith(color: colors.text2),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    children: [
                      Container(color: colors.border),
                      FractionallySizedBox(
                        widthFactor: fraction,
                        child: Container(color: colors.statusDone),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
