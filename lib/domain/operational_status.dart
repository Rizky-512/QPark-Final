import '../data/remote_repository.dart';

enum OperationalStatus { unpaid, paid, authorized }

OperationalStatus operationalStatus(Json session, double now) {
  final auth = session['authorization'] as Map?;
  if (session['state'] == 'EXIT_AUTHORIZED' &&
      auth?['expires_at'] is num &&
      (auth!['expires_at'] as num) > now) {
    return OperationalStatus.authorized;
  }
  final due = (session['invoices'] as List? ?? []).any(
    (i) => i['state'] == 'PENDING',
  );
  final window = session['window'] as Map?;
  if (!due &&
      session['window_status'] == 'VALID' &&
      window?['deadline'] is num &&
      (window!['deadline'] as num) >= now) {
    return OperationalStatus.paid;
  }
  return OperationalStatus.unpaid;
}

String operationalLabel(OperationalStatus value) => switch (value) {
  OperationalStatus.unpaid => 'Belum bayar',
  OperationalStatus.paid => 'Sudah bayar',
  OperationalStatus.authorized => 'Diizinkan keluar',
};
