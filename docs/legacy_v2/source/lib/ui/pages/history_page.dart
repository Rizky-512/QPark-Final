import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../common.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.args});
  final ScreenArgs args;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTime start = DateTime.now(), end = DateTime.now();
  Vehicle? vehicle;
  final search = TextEditingController();
  late Future<(List<Visit>, Revenue?)> future;
  bool get admin => widget.args.session.user.role == Role.admin;
  @override
  void initState() {
    super.initState();
    future = load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<(List<Visit>, Revenue?)> load() async {
    final filter = HistoryFilter(
      start: start,
      end: end,
      vehicle: vehicle,
      query: search.text,
    );
    final visits = await widget.args.service.history(
      widget.args.session,
      filter,
    );
    final revenue = admin
        ? await widget.args.service.revenue(widget.args.session, filter)
        : null;
    return (visits, revenue);
  }

  void reload() {
    final next = load();
    setState(() {
      future = next;
    });
  }

  Future<void> chooseDate(bool first) async {
    final value = await showDatePicker(
      context: context,
      initialDate: first ? start : end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: first ? 'Tanggal awal' : 'Tanggal akhir',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (value != null && mounted) {
      setState(() {
        if (first) {
          start = value;
        } else {
          end = value;
        }
      });
      reload();
    }
  }

  Future<void> detail(Visit v) async {
    try {
      final fresh = await widget.args.service.detail(widget.args.session, v.id);
      if (mounted) await showReceipt(context, fresh);
    } catch (e) {
      if (mounted) widget.args.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHeading(
        'Riwayat transaksi',
        admin
            ? 'Transaksi lunas dan pendapatan parkir.'
            : 'Telusuri kendaraan yang sudah keluar.',
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => chooseDate(true),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('Dari: ${dateText(start)}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => chooseDate(false),
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Sampai: ${dateText(end)}'),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<Vehicle?>(
                    initialValue: vehicle,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Jenis kendaraan',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Semua jenis'),
                      ),
                      ...Vehicle.values.map(
                        (v) => DropdownMenuItem(value: v, child: Text(v.label)),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => vehicle = v);
                      reload();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: search,
              onSubmitted: (_) => reload(),
              decoration: InputDecoration(
                labelText: 'Cari pelat atau ID transaksi',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Terapkan pencarian',
                  onPressed: reload,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Filter berdasarkan waktu keluar, mencakup seluruh tanggal awal dan akhir.',
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      LoadPanel(
        future: future,
        retry: reload,
        onExpired: widget.args.expire,
        builder: (result) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (result.$2 != null) ...[
              SurfaceCard(
                child: Wrap(
                  spacing: 48,
                  runSpacing: 18,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pendapatan',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          money(result.$2!.total),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Transaksi lunas',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${result.$2!.count}',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            SurfaceCard(
              child: result.$1.isEmpty
                  ? const EmptyState(
                      title: 'Belum ada transaksi lunas',
                      description:
                          'Ubah filter atau selesaikan pembayaran kendaraan terlebih dahulu.',
                    )
                  : VisitList(visits: result.$1, onSelect: detail),
            ),
          ],
        ),
      ),
    ],
  );
}
