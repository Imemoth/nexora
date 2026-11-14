import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'sha256.dart';

void main() {
  test('HMAC-SHA256 matches RFC 4231 test case 1', () {
    final mac = hmacSha256(List<int>.filled(20, 0x0b), utf8.encode('Hi There'));
    expect(
      bytesToHex(mac),
      'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
    );
  });

  test('HMAC-SHA256 with a key longer than a block (RFC 4231 case 6)', () {
    final mac = hmacSha256(
      List<int>.filled(131, 0xaa),
      utf8.encode('Test Using Larger Than Block-Size Key - Hash Key First'),
    );
    expect(
      bytesToHex(mac),
      '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54',
    );
  });
}
