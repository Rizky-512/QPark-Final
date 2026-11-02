import 'dart:math';
import '../data/remote_repository.dart';

class ParkingCost {
  const ParkingCost({
    required this.seconds,
    required this.hours,
    required this.rate,
    required this.amount,
    required this.serverInvoice,
    required this.additional,
  });
  final int seconds, hours, rate, amount;
  final bool serverInvoice, additional;

  factory ParkingCost.fromSession(Json session, double now) {
    final entered = (session['entered_at'] as num?)?.toDouble();
    final end = (session['exited_at'] as num?)?.toDouble() ?? now;
    final seconds = entered == null || now <= 0
        ? (session['duration_seconds'] as num? ?? 0).toInt()
        : max(0, (end - entered).floor());
    final hours = max(1, seconds ~/ 3600);
    final rate = (session['hourly_rate'] as num? ?? 0).toInt();
    final invoices = (session['invoices'] as List? ?? []).cast<Json>();
    final due = invoices
        .where(
          (i) =>
              i['state'] == 'PENDING' &&
              (i['expires_at'] == null || (i['expires_at'] as num) > now),
        )
        .toList();
    final paid =
        invoices.any((i) => i['state'] == 'PAID') ||
        (session['amount_paid'] as num? ?? 0) > 0;
    final deadline = (session['window'] as Map?)?['deadline'];
    final additional =
        paid &&
        session['state'] == 'IN_AREA' &&
        deadline is num &&
        now > deadline;
    final amount = session['state'] == 'COMPLETED'
        ? 0
        : due.isNotEmpty
        ? due.fold<int>(0, (total, i) => total + (i['amount'] as num).toInt())
        : paid
        ? (additional ? rate : 0)
        : hours * rate;
    return ParkingCost(
      seconds: seconds,
      hours: hours,
      rate: rate,
      amount: amount,
      serverInvoice: due.isNotEmpty,
      additional: additional || due.any((i) => i['kind'] == 'PENALTY'),
    );
  }
}
