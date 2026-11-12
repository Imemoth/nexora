import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/runtime/runtime_config.dart';

import '../support/fake_auth.dart';

String _key(String role) => fakeJwt(
  sub: userA,
  expiresAt: DateTime.utc(2035),
  role: role,
);

void main() {
  test('https project settings with an anon key are accepted', () {
    final c = RuntimeConfig.validate('https://abc.supabase.co/', _key('anon'))!;
    expect(c.supabaseUrl, 'https://abc.supabase.co');
  });

  test('a service-role key is refused: it can never be in the application', () {
    expect(
      RuntimeConfig.validate('https://abc.supabase.co', _key('service_role')),
      isNull,
    );
  });

  test('plain http is allowed only for this machine', () {
    expect(RuntimeConfig.validate('http://127.0.0.1:54321', _key('anon')), isNotNull);
    expect(RuntimeConfig.validate('http://localhost:54321', _key('anon')), isNotNull);
    expect(RuntimeConfig.validate('http://abc.supabase.co', _key('anon')), isNull);
  });

  test('missing or malformed settings are refused', () {
    expect(RuntimeConfig.validate(null, 'k'), isNull);
    expect(RuntimeConfig.validate('https://x.y', ''), isNull);
    expect(RuntimeConfig.validate('not a url', 'k'), isNull);
    expect(RuntimeConfig.validate('ftp://x.y', 'k'), isNull);
  });
}
