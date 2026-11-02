import 'package:intl/intl.dart';
import '../data/remote_repository.dart';

class ParkingReceipt {
  ParkingReceipt.fromSession(Json session) : text = _create(session);
  final String text;
  static bool available(Json session) =>
      (session['invoices'] as List? ?? []).any((i) => i['state'] == 'PAID');

  static String _money(num value) => NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  ).format(value);
  static String _time(dynamic seconds) {
    if (seconds is! num) return 'Belum tercatat';
    final time = DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000).round(),
      isUtc: true,
    ).add(const Duration(hours: 7));
    return '${DateFormat('dd/MM/yyyy HH:mm:ss').format(time)} WIB';
  }

  static String _create(Json session) {
    final paid = (session['invoices'] as List? ?? [])
        .cast<Json>()
        .where((i) => i['state'] == 'PAID')
        .toList();
    if (paid.isEmpty) throw StateError('Belum ada pembayaran terkonfirmasi.');
    final simulated = paid.any((i) => i['payment_method'] == 'QR_SIMULASI');
    final total = paid.fold<num>(
      0,
      (sum, invoice) => sum + (invoice['amount'] as num),
    );
    return [
      'QPARK - BUKTI TRANSAKSI PROTOTIPE',
      if (simulated) 'SIMULASI - pembayaran QR tidak memindahkan uang nyata',
      'Tiket: ${session['id']}',
      'Nopol: ${session['plate']}',
      'Kendaraan: ${session['vehicle_type'] == 'MOTOR' ? 'Motor' : 'Mobil'}',
      'Masuk: ${_time(session['entered_at'])}',
      'Keluar: ${session['exited_at'] == null ? 'Belum keluar' : _time(session['exited_at'])}',
      'Tarif sesi: ${_money(session['hourly_rate'] as num? ?? 0)}/jam',
      'Aturan: minimum 1 jam, jam penuh dibulatkan ke bawah.',
      '',
      for (final invoice in paid) ...[
        'Transaksi/tagihan: ${invoice['id']}',
        '${invoice['kind'] == 'PENALTY' ? 'Tambahan keterlambatan' : 'Parkir'}: ${invoice['hours'] ?? 1} jam | ${_money(invoice['amount'] as num)}',
        'Metode: ${invoice['payment_method'] == 'QR_SIMULASI'
            ? 'QR SIMULASI'
            : invoice['payment_method'] == 'MANUAL'
            ? 'Manual (dicatat petugas)'
            : 'Tidak tercatat'}',
        'Dibayar: ${_time(invoice['paid_at'])}',
        if (invoice['received'] is num)
          'Diterima: ${_money(invoice['received'] as num)} | Kembalian: ${_money(invoice['change_amount'] as num? ?? 0)}',
        '',
      ],
      'TOTAL TERCATAT: ${_money(total)}',
      'Bukti ini hanya memuat pembayaran yang sudah terkonfirmasi pada server.',
    ].join('\n');
  }
}
