import 'package:flutter/material.dart';
import '../data/remote_repository.dart';
import '../logic/remote_service.dart';
import 'common.dart';

class RemoteArgs {
  const RemoteArgs(
    this.service,
    this.navigate, {
    this.openCheckout,
    this.openQrPay,
    this.openEvBook,
  });
  final RemoteService service;
  final void Function(int) navigate;
  final void Function(String sessionId)? openCheckout;
  final VoidCallback? openQrPay;
  final void Function([String? locationId])? openEvBook;
}

String wib(dynamic seconds) {
  if (seconds is! num) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(
    (seconds * 1000).round(),
    isUtc: true,
  ).add(const Duration(hours: 7));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}:${two(d.second)} WIB';
}

String remaining(dynamic deadline, double now) {
  if (deadline is! num) return '—';
  final seconds = (deadline - now).ceil().clamp(0, 86400);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String stateLabel(Json s) => switch (s['state']) {
  'COMPLETED' => 'Selesai',
  'EXIT_AUTHORIZED' => 'Diizinkan keluar',
  _ => s['payment_status'] as String? ?? 'Di dalam',
};
void remoteError(BuildContext context, Object error) =>
    showMessage(context, error.toString(), error: true);

class CapacityCard extends StatelessWidget {
  const CapacityCard(this.service, {super.key});
  final RemoteService service;
  @override
  Widget build(BuildContext context) {
    final data = service.capacity;
    final categories = data?['categories'] as Map?;
    final loc = data?['location'] as Map?;
    final locName = loc?['name'] as String?;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            locName == null ? 'Ketersediaan parkir' : 'Ketersediaan · $locName',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          for (final kind in ['MOBIL', 'MOTOR']) ...[
            Builder(
              builder: (context) {
                final c = categories?[kind] as Map?;
                final total = (c?['total'] as num?)?.toInt() ?? 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          kind == 'MOBIL'
                              ? Icons.directions_car
                              : Icons.two_wheeler,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            kind == 'MOBIL' ? 'Parkir Mobil' : 'Parkir Motor',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        StatusPill(
                          c == null
                              ? 'Belum tersedia'
                              : !service.online
                              ? 'Data terakhir'
                              : c['full'] == true
                              ? 'Penuh'
                              : 'Tersedia',
                          pending: c == null || !service.online,
                          problem: c?['full'] == true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c == null
                          ? 'Sisa slot belum tersedia'
                          : "${c['available']} slot tersedia",
                      key: ValueKey('capacity-$kind'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: AppColors.primary),
                    ),
                    if (c != null) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: total == 0
                            ? 1
                            : ((c['occupied'] as num) / total).clamp(0.0, 1.0),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "${c['occupied']} terisi / $total kapasitas",
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
          ],
          if (data?['ev'] is Map) ...[
            Builder(
              builder: (context) {
                final ev = data!['ev'] as Map;
                final total = (ev['total'] as num?)?.toInt() ?? 0;
                final occupied = (ev['occupied'] as num?)?.toInt() ?? 0;
                final available = (ev['available'] as num?)?.toInt() ?? 0;
                final full = ev['full'] == true;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.ev_station_rounded,
                          color: Color(0xFF0284C7),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'EV Charging Station',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        StatusPill(
                          !service.online
                              ? 'Data terakhir'
                              : full
                              ? 'Penuh'
                              : 'Tersedia',
                          pending: !service.online,
                          problem: full,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$available slot EV tersedia',
                      key: const ValueKey('capacity-EV'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: const Color(0xFF0284C7)),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      color: const Color(0xFF0284C7),
                      value: total == 0
                          ? 1
                          : (occupied / total).clamp(0.0, 1.0),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$occupied terisi / $total slot EV · ${money((ev['rate'] as num?)?.toInt() ?? 10000)}/jam',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
          ],
          if (data != null)
            Text(
              "Pembaruan: ${wib(data['server_time'])}",
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          if (!service.online)
            const Text(
              'Koneksi terputus. Data belum diperbarui.',
              style: TextStyle(color: AppColors.danger),
            ),
          const Text(
            'Informasi ketersediaan, bukan reservasi.',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class SessionSummary extends StatelessWidget {
  const SessionSummary(this.session, {super.key});
  final Json session;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            session['plate'] as String,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          StatusPill(
            stateLabel(session),
            problem: session['window_status'] == 'EXPIRED',
            pending:
                session['state'] == 'IN_AREA' &&
                session['window_status'] != 'VALID',
          ),
        ],
      ),
      const SizedBox(height: 12),
      SelectableText(
        'Tiket: ${session['id']}',
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
      if (session['location_name'] is String &&
          (session['location_name'] as String).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  session['location_name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      Text(
        '${session['vehicle_type'] == 'MOTOR' ? 'Motor' : 'Mobil'} · ${money((session['hourly_rate'] as num? ?? 7000).toInt())}/jam',
      ),
      Text('Masuk: ${wib(session['entered_at'])}'),
      Text(
        'Durasi: ${durationText(Duration(seconds: (session['duration_seconds'] as num).toInt()))}',
      ),
      Text('Total lunas: ${money((session['amount_paid'] as num).toInt())}'),
      if (session['window'] != null)
        Text('Batas keluar: ${wib(session['window']['deadline'])}'),
      if (session['exited_at'] != null)
        Text('Keluar: ${wib(session['exited_at'])}'),
    ],
  );
}
