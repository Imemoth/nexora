/// Named colour tokens for the approved dark theme. Pure Dart ARGB values so
/// the contrast checks run without Flutter. Light theme is deferred (decision 7).
abstract final class NexoraPalette {
  static const int background = 0xFF0E1116;
  static const int surface = 0xFF161B22;
  static const int surface2 = 0xFF1F262F;
  static const int border = 0xFF3A4450;
  static const int text1 = 0xFFE6EDF3;
  static const int text2 = 0xFFB1BCC9;
  static const int textMuted = 0xFF8B97A6;
  static const int primary = 0xFF6CB6FF;
  static const int positive = 0xFF56D364;
  static const int negative = 0xFFFF7B72;
  static const int warning = 0xFFE3B341;
}
