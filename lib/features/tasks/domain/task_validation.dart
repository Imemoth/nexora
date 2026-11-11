import 'package:nexora/core/result.dart';

/// Maximum stored title length, counted in UTF-16 code units.
const int maxTitleLength = 200;

/// Reasons a title is rejected.
enum TitleError { required, tooLong }

/// Trims [raw] and checks that it is a valid title. The trimmed value is what
/// gets stored.
Result<String, TitleError> validateTitle(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const Err<String, TitleError>(TitleError.required);
  }
  if (trimmed.length > maxTitleLength) {
    return const Err<String, TitleError>(TitleError.tooLong);
  }
  return Ok<String, TitleError>(trimmed);
}
