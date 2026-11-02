import 'dart:convert';
import 'rules.dart';

class CustomerLinkQr {
  const CustomerLinkQr(this.plate, this.code, this.expiresAt);
  final String plate, code;
  final int expiresAt;
  String encode() =>
      'QPL1:${base64Url.encode(utf8.encode(jsonEncode({'plate': plate, 'code': code, 'expires': expiresAt})))}';

  static CustomerLinkQr parse(String value, {required double now}) {
    try {
      if (!value.startsWith('QPL1:') || value.length > 512) {
        throw const FormatException();
      }
      final data = jsonDecode(
        utf8.decode(base64Url.decode(value.substring(5))),
      );
      if (data is! Map ||
          data['plate'] is! String ||
          data['code'] is! String ||
          data['expires'] is! int) {
        throw const FormatException();
      }
      final plate = normalizePlate(data['plate'] as String);
      final code = data['code'] as String;
      if (!RegExp(r'^[A-F0-9]{12}$').hasMatch(code) ||
          (data['expires'] as int) <= now) {
        throw const FormatException();
      }
      return CustomerLinkQr(plate, code, data['expires'] as int);
    } catch (_) {
      throw const FormatException(
        'QR penghubung tidak valid atau kedaluwarsa. Minta kode baru dari pelanggan.',
      );
    }
  }
}
