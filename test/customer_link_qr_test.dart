import 'package:flutter_test/flutter_test.dart';
import 'package:qpark/domain/customer_link_qr.dart';

void main() {
  test('link QR roundtrip keeps code, plate and deadline', () {
    const value = CustomerLinkQr('B123AB', '012345ABCDEF', 1000);
    final decoded = CustomerLinkQr.parse(value.encode(), now: 999);
    expect(decoded.plate, value.plate);
    expect(decoded.code, value.code);
    expect(decoded.expiresAt, 1000);
  });
  test('exit, malformed, oversized and expired QR are rejected', () {
    for (final value in [
      'QPX.exit.token',
      'QPL1:bad',
      'QPL1:${'a' * 600}',
      const CustomerLinkQr('B123AB', '012345ABCDEF', 1000).encode(),
      const CustomerLinkQr('B123AB', 'bad', 2000).encode(),
    ]) {
      expect(
        () => CustomerLinkQr.parse(value, now: 1000),
        throwsFormatException,
      );
    }
  });
}
