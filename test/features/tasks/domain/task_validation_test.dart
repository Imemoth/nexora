import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/task_validation.dart';

import '../../../support/result_matchers.dart';

void main() {
  group('validateTitle', () {
    test('trims surrounding whitespace before storing', () {
      final result = validateTitle('  Buy milk  ');

      expect(okValue(result), 'Buy milk');
    });

    test('rejects an empty title', () {
      expect(errValue(validateTitle('')), TitleError.required);
    });

    test('rejects a whitespace-only title', () {
      expect(errValue(validateTitle('   \t ')), TitleError.required);
    });

    test('accepts a title of exactly the maximum length', () {
      final title = 'a' * maxTitleLength;

      expect(okValue(validateTitle(title)), title);
    });

    test('rejects a title one character over the maximum length', () {
      final title = 'a' * (maxTitleLength + 1);

      expect(errValue(validateTitle(title)), TitleError.tooLong);
    });

    test('measures length after trimming', () {
      final padded = '  ${'a' * maxTitleLength}  ';

      expect(okValue(validateTitle(padded)).length, maxTitleLength);
    });
  });
}
