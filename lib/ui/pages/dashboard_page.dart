import 'package:flutter/material.dart';
import '../common.dart';
import '../remote_common.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.args});
  final RemoteArgs args;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final service = widget.args.service;
    final rows = service.sessions
        .where(
          (s) => (s['plate'] as String).contains(
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
              if (rows.isEmpty)
                EmptyState(
                  title: query.isEmpty
                      ? 'Belum ada kendaraan'
                      : 'Nopol tidak ditemukan',
                  description: query.isEmpty
                      ? 'Gunakan Catat kendaraan masuk untuk menerima kendaraan.'
                      : 'Periksa ejaan nopol atau hapus pencarian.',
                ),
              ...rows.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SurfaceCard(
                    padding: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SessionSummary(s),
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
