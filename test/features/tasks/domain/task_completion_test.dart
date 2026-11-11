import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/task_completion.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

void main() {
  group('summarizeChildren', () {
    test('no children: zero totals and not eligible for review', () {
      final result = summarizeChildren(const <TaskStatus>[]);

      expect(result.total, 0);
      expect(result.done, 0);
      expect(result.eligibleForReview, isFalse);
    });

    test('all children done: eligible for review, not closed', () {
      final result = summarizeChildren(const [
        TaskStatus.done,
        TaskStatus.done,
      ]);

      expect(result.total, 2);
      expect(result.done, 2);
      expect(result.eligibleForReview, isTrue);
    });

    test('partially done: not eligible for review', () {
      final result = summarizeChildren(const [
        TaskStatus.done,
        TaskStatus.inProgress,
      ]);

      expect(result.total, 2);
      expect(result.done, 1);
      expect(result.eligibleForReview, isFalse);
    });

    test('archived child counts toward total but not toward done', () {
      final result = summarizeChildren(const [TaskStatus.archived]);

      expect(result.total, 1);
      expect(result.done, 0);
      expect(result.eligibleForReview, isFalse);
    });

    test('review and open children are not done', () {
      final result = summarizeChildren(const [
        TaskStatus.review,
        TaskStatus.open,
      ]);

      expect(result.total, 2);
      expect(result.done, 0);
      expect(result.eligibleForReview, isFalse);
    });
  });
}
