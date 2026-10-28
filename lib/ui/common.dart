import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../domain/errors.dart';
import '../domain/models.dart';
import '../logic/services.dart';

abstract final class AppColors {
  static const primary = Color(0xFF166534),
      accent = Color(0xFF0F766E),
      background = Color(0xFFF3F8F4),
      surface = Color(0xFFFFFFFF),
      text = Color(0xFF172C20),
      muted = Color(0xFF53655A),
      border = Color(0xFFD6E4DA),
      successBackground = Color(0xFFEAF5ED),
      danger = Color(0xFFB42318),
      dangerBackground = Color(0xFFFDEDEB);
}

ThemeData buildTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
  ),
  scaffoldBackgroundColor: AppColors.background,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.surface,
    foregroundColor: AppColors.text,
    surfaceTintColor: AppColors.surface,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  cardTheme: CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.border),
    ),
  ),
  dividerTheme: const DividerThemeData(color: AppColors.border),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
);
String money(int? value) =>
    'Rp${NumberFormat.decimalPattern('id_ID').format(value ?? 0)}';
String dateTimeText(DateTime time) =>
    DateFormat('dd MMM yyyy, HH:mm:ss', 'id_ID').format(time.toLocal());
String dateText(DateTime time) =>
    DateFormat('dd MMM yyyy', 'id_ID').format(time);
String durationText(Duration d) =>
    '${d.inHours} jam ${d.inMinutes.remainder(60)} menit ${d.inSeconds.remainder(60)} detik';
IconData vehicleIcon(Vehicle v) => v == Vehicle.motor
    ? Icons.two_wheeler_rounded
    : Icons.directions_car_rounded;

class ScreenArgs {
  const ScreenArgs({
    required this.service,
    required this.session,
    required this.dirty,
    required this.busy,
    required this.expire,
    required this.navigate,
  });
  final QParkService service;
  final Session session;
  final void Function(bool) dirty, busy;
  final VoidCallback expire;
  final void Function(int) navigate;
  void error(BuildContext context, Object error) {
    if (error is SessionExpired) expire();
    if (!context.mounted) return;
    showMessage(
      context,
      error is QParkException
          ? error.message
          : 'Terjadi kesalahan. Silakan coba lagi.',
      error: true,
    );
  }
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: error ? AppColors.danger : AppColors.primary,
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            color: AppColors.surface,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  String action = 'Lanjutkan',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        scrollable: true,
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      spacing: 20,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
        ?action,
      ],
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = 20});
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.problem = false,
    this.pending = false,
  });
  final String label;
  final bool problem;
  final bool pending;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: problem
          ? AppColors.dangerBackground
          : pending
          ? AppColors.background
          : AppColors.successBackground,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          problem
              ? Icons.block_rounded
              : pending
              ? Icons.schedule
              : Icons.check_circle_outline_rounded,
          size: 16,
          color: problem ? AppColors.danger : AppColors.primary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: problem ? AppColors.danger : AppColors.primary,
            ),
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.title = 'Belum ada kendaraan',
    this.description = 'Kendaraan yang masuk akan tampil di sini.',
  });
  final String title, description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Center(
      child: Column(
        children: [
          const Icon(
            Icons.local_parking_rounded,
            size: 44,
            color: AppColors.accent,
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class LoadPanel<T> extends StatelessWidget {
  const LoadPanel({
    super.key,
    required this.future,
    required this.builder,
    required this.retry,
    this.onExpired,
  });
  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback retry;
  final VoidCallback? onExpired;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(48),
          child: Center(
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Memuat data…'),
              ],
            ),
          ),
        );
      }
      if (snapshot.hasError) {
        final error = snapshot.error;
        return SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.danger,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                error is QParkException
                    ? error.message
                    : 'Data belum dapat dimuat. Coba lagi.',
                style: const TextStyle(color: AppColors.danger),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: error is SessionExpired ? onExpired : retry,
                icon: Icon(
                  error is SessionExpired ? Icons.login : Icons.refresh,
                ),
                label: Text(
                  error is SessionExpired ? 'Masuk kembali' : 'Coba lagi',
                ),
              ),
            ],
          ),
        );
      }
      return builder(snapshot.data as T);
    },
  );
}

class VisitList extends StatefulWidget {
  const VisitList({
    super.key,
    required this.visits,
    required this.onSelect,
    this.action = 'Lihat detail',
  });
  final List<Visit> visits;
  final void Function(Visit) onSelect;
  final String action;
  @override
  State<VisitList> createState() => _VisitListState();
}

class _VisitListState extends State<VisitList> {
  int page = 0;
  static const perPage = 15;
  @override
  void didUpdateWidget(VisitList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visits != widget.visits) page = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visits.isEmpty) return const EmptyState();
    final rows = widget.visits.skip(page * perPage).take(perPage).toList();
    return LayoutBuilder(
      builder: (context, bounds) => Column(
        children: [
          if (bounds.maxWidth >= 760)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 28,
                headingRowColor: const WidgetStatePropertyAll(
                  AppColors.successBackground,
                ),
                columns: const [
                  DataColumn(label: Text('Nomor polisi')),
                  DataColumn(label: Text('Jenis')),
                  DataColumn(label: Text('Waktu masuk')),
                  DataColumn(label: Text('Status / biaya')),
                  DataColumn(label: Text('Tindakan')),
                ],
                rows: rows
                    .map(
                      (v) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              v.plate,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataCell(Text(v.vehicle.label)),
                          DataCell(Text(dateTimeText(v.enteredAt))),
                          DataCell(
                            v.active
                                ? const StatusPill('Aktif')
                                : Text(money(v.total)),
                          ),
                          DataCell(
                            TextButton(
                              onPressed: () => widget.onSelect(v),
                              child: Text(widget.action),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            )
          else
            ...rows.map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SurfaceCard(
                  padding: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            vehicleIcon(v.vehicle),
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              v.plate,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(v.vehicle.label),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        dateTimeText(v.enteredAt),
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusPill(
                            v.active
                                ? 'Aktif · Belum bayar'
                                : 'Selesai · Lunas',
                          ),
                          if (!v.active) Text(money(v.total)),
                          TextButton(
                            onPressed: () => widget.onSelect(v),
                            child: Text(widget.action),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.visits.length > perPage)
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Halaman sebelumnya',
                  onPressed: page == 0 ? null : () => setState(() => page--),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '${page * perPage + 1}–${page * perPage + rows.length} dari ${widget.visits.length}',
                ),
                IconButton(
                  tooltip: 'Halaman berikutnya',
                  onPressed: (page + 1) * perPage >= widget.visits.length
                      ? null
                      : () => setState(() => page++),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class DetailLine extends StatelessWidget {
  const DetailLine(this.label, this.value, {super.key, this.emphasis = false});
  final String label, value;
  final bool emphasis;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SelectableText(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: emphasis ? FontWeight.w800 : FontWeight.w500,
              color: emphasis ? AppColors.primary : AppColors.text,
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> showReceipt(BuildContext context, Visit visit) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(visit.active ? 'Kendaraan masuk' : 'Bukti pembayaran'),
    content: SizedBox(
      width: 470,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              visit.active ? Icons.local_parking : Icons.verified_outlined,
              size: 42,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            Text(visit.plate, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            StatusPill(visit.status),
            const SizedBox(height: 16),
            DetailLine('ID transaksi', visit.id),
            DetailLine('Jenis kendaraan', visit.vehicle.label),
            DetailLine('Waktu masuk', dateTimeText(visit.enteredAt)),
            DetailLine('Petugas masuk', visit.entryOfficerName),
            DetailLine('Tarif saat masuk', '${money(visit.hourlyRate)}/jam'),
            if (!visit.active) ...[
              DetailLine('Waktu keluar', dateTimeText(visit.exitedAt!)),
              DetailLine(
                'Durasi aktual',
                durationText(visit.exitedAt!.difference(visit.enteredAt)),
              ),
              DetailLine('Jam tertagih', '${visit.hours} jam'),
              const Divider(),
              DetailLine('Total biaya', money(visit.total), emphasis: true),
              const DetailLine('Metode pembayaran', 'Tunai'),
              DetailLine('Uang diterima', money(visit.received)),
              DetailLine('Kembalian', money(visit.change), emphasis: true),
              DetailLine('Petugas keluar', visit.exitOfficerName ?? '—'),
            ],
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Tutup'),
      ),
    ],
  ),
);
