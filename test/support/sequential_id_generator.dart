import 'package:nexora/core/ids/id_generator.dart';

/// Deterministic ids for tests. Throws a RangeError when exhausted.
final class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator(this._ids);

  final List<String> _ids;
  int _next = 0;

  @override
  String nextId() {
    return _ids[_next++];
  }
}
