import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../common.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.args});
  final ScreenArgs args;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final search = TextEditingController();
  late Future<Dashboard> future;
  @override
  void initState() {
    super.initState();
    future = widget.args.service.dashboard(widget.args.session);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void reload() {
    final next = widget.args.service.dashboard(
      widget.args.session,
      search.text,
    );
    setState(() {
      future = next;
    });
  }

  Future<void> detail(Visit v) async {
    try {
      final visit = await widget.args.service.detail(widget.args.session, v.id);
      if (mounted) await showReceipt(context, visit);
    } catch (e) {
      if (mounted) widget.args.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHeading(
        'Ringkasan parkir',
        'Pantau ketersediaan tempat parkir saat ini.',
        action: OutlinedButton.icon(
          onPressed: reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Muat ulang'),
        ),
      ),
      LoadPanel(
        future: future,
        retry: reload,
        onExpired: widget.args.expire,
        builder: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, bounds) => Wrap(
                spacing: 16,
                runSpacing: 16,
                children: data.slots
                    .map(
                      (slot) => SizedBox(
                        width: bounds.maxWidth >= 560
                            ? (bounds.maxWidth - 16) / 2
                            : bounds.maxWidth,
                        child: SurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    vehicleIcon(slot.vehicle),
                                    color: AppColors.primary,
                                    size: 32,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      slot.vehicle.label,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ),
                                  StatusPill(
                                    slot.full ? 'Penuh' : 'Tersedia',
                                    problem: slot.full,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${slot.available}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .displayMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primary,
                                        ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.only(
                                      left: 10,
                                      bottom: 10,
                                    ),
                                    child: Text(
                                      'slot tersedia',
                                      style: TextStyle(color: AppColors.muted),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              LinearProgressIndicator(
                                value: slot.capacity == 0
                                    ? 1
                                    : slot.occupied / slot.capacity,
                                color: slot.full
                                    ? AppColors.danger
                                    : AppColors.accent,
                                backgroundColor: AppColors.successBackground,
                                borderRadius: BorderRadius.circular(8),
                                minHeight: 7,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${slot.occupied} terisi · ${slot.capacity} kapasitas',
                                style: const TextStyle(color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 28),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Kendaraan aktif',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('active-search'),
                    controller: search,
                    onSubmitted: (_) => reload(),
                    decoration: InputDecoration(
                      labelText: 'Cari pelat atau ID transaksi',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Cari kendaraan',
                        onPressed: reload,
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  VisitList(visits: data.visits, onSelect: detail),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
