import 'package:flutter/material.dart';
import '../data/remote_repository.dart';
import '../logic/remote_service.dart';
import 'common.dart';

class RemoteArgs {
  const RemoteArgs(this.service, this.navigate);
  final RemoteService service;
  final void Function(int) navigate;
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
    final c = service.capacity;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.directions_car_rounded,
                color: AppColors.primary,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Parkir mobil & motor',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StatusPill(
                c == null
                    ? 'Belum tersedia'
                    : c['full'] == true
                    ? 'Penuh'
                    : 'Tersedia',
                problem: c?['full'] == true,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(
                c == null ? '—' : '${c['available']}',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const Text(
                'tempat kosong',
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (c != null) ...[
            LinearProgressIndicator(
              value: (c['occupied'] as num) / (c['total'] as num),
              color: c['full'] == true ? AppColors.danger : AppColors.accent,
              backgroundColor: AppColors.successBackground,
              borderRadius: BorderRadius.circular(8),
              minHeight: 7,
            ),
            const SizedBox(height: 12),
            Text('${c['occupied']} terisi · ${c['total']} kapasitas'),
            const SizedBox(height: 8),
            Text(
              'Pembaruan: ${wib(c['server_time'])}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
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
          ),
        ],
      ),
      const SizedBox(height: 12),
      SelectableText(
        'Tiket: ${session['id']}',
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
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
