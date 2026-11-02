import 'package:flutter/material.dart';
import '../common.dart';
import '../remote_common.dart';
import '../../domain/operational_status.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.args});
  final RemoteArgs args;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String query = '';
  OperationalStatus? statusFilter;
  @override
  Widget build(BuildContext context) {
    final service = widget.args.service;
    final rows = service.sessions
        .where(
          (s) =>
              (statusFilter == null ||
                  operationalStatus(s, service.serverNow) == statusFilter) &&
              (s['plate'] as String).contains(
                query.toUpperCase().replaceAll(' ', ''),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          'Ringkasan parkir',
          'Pantau ketersediaan dan status kendaraan di dalam.',
          action: OutlinedButton.icon(
            onPressed: service.sync,
            icon: const Icon(Icons.refresh),
            label: const Text('Muat ulang'),
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => widget.args.navigate(1),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Catat kendaraan masuk'),
            ),
            OutlinedButton.icon(
              onPressed: () => widget.args.navigate(2),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Pembayaran & keluar'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        CapacityCard(service),
        const SizedBox(height: 24),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Kendaraan aktif',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('active-search'),
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  labelText: 'Cari nopol',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Semua (${service.sessions.length})'),
                    selected: statusFilter == null,
                    onSelected: (_) => setState(() => statusFilter = null),
                  ),
                  for (final status in OperationalStatus.values)
                    ChoiceChip(
                      label: Text(
                        '${operationalLabel(status)} (${service.sessions.where((s) => operationalStatus(s, service.serverNow) == status).length})',
                      ),
                      selected: statusFilter == status,
                      onSelected: (_) => setState(() => statusFilter = status),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('${rows.length} kendaraan ditampilkan'),
              if (rows.isEmpty)
                EmptyState(
                  title: query.isEmpty && statusFilter == null
                      ? 'Belum ada kendaraan'
                      : 'Tidak ada kendaraan yang cocok',
                  description: query.isEmpty && statusFilter == null
                      ? 'Gunakan Catat kendaraan masuk untuk menerima kendaraan.'
                      : 'Periksa nopol atau pilih filter status lainnya.',
                ),
              ...rows.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SurfaceCard(
                    padding: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              s['plate'] as String,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            StatusPill(
                              operationalLabel(
                                operationalStatus(s, service.serverNow),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${s['vehicle_type'] == 'MOTOR' ? 'Motor' : 'Mobil'} | Masuk ${wib(s['entered_at'])}',
                        ),
                        Text(
                          'Sudah dibayar ${money((s['amount_paid'] as num? ?? 0).toInt())}',
                        ),
                        FilledButton.tonalIcon(
                          onPressed: !service.online
                              ? null
                              : () {
                                  final open = widget.args.openCheckout;
                                  if (open != null) {
                                    open(s['id'] as String);
                                  } else {
                                    widget.args.navigate(2);
                                  }
                                },
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(
                            operationalStatus(s, service.serverNow) ==
                                    OperationalStatus.authorized
                                ? 'Konfirmasi kendaraan lewat'
                                : operationalStatus(s, service.serverNow) ==
                                      OperationalStatus.paid
                                ? 'Verifikasi & izinkan keluar'
                                : 'Buka tagihan kendaraan',
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (s['authorization'] != null)
                          Text(
                            'Konfirmasi sebelum: ${wib(s['authorization']['expires_at'])}',
                          ),
                        TextButton.icon(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(s['plate'] as String),
                              content: SingleChildScrollView(
                                child: SessionSummary(s),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Tutup'),
                                ),
                              ],
                            ),
                          ),
                          icon: const Icon(Icons.info_outline),
                          label: const Text('Detail tiket'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
