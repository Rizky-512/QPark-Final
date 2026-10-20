import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

/// Hash satu arah dengan salt acak, tanpa kata sandi asli.
class PasswordSecurity {
  PasswordSecurity({this.iterations = 600000});
  final int iterations;
  String randomToken() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(24, (_) => random.nextInt(256)));
  }

  Future<String> hash(String password) async {
    final salt = base64Url.decode(randomToken());
    final bytes = await _derive(password, salt, iterations);
    return 'pbkdf2_sha256\$$iterations\$${base64Encode(salt)}\$${base64Encode(bytes)}';
  }

  Future<bool> verify(String password, String encoded) async {
    try {
      final parts = encoded.split(r'$');
      if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
      final rounds = int.parse(parts[1]);
      if (rounds < 1000 || rounds > 2000000) return false;
      final expected = base64Decode(parts[3]);
      final actual = await _derive(password, base64Decode(parts[2]), rounds);
      if (expected.length != actual.length) return false;
      var diff = 0;
      for (var i = 0; i < expected.length; i++) {
        diff |= expected[i] ^ actual[i];
      }
      return diff == 0;
    } on FormatException {
      return false;
    }
  }

  Future<List<int>> _derive(String password, List<int> salt, int rounds) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: rounds,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    return key.extractBytes();
  }
}
