import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../data/remote_repository.dart';
import '../common.dart';
import '../remote_common.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key, required this.args, required this.active});
  final RemoteArgs args;
  final bool active;
  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  Json? data;
  String? error;
  bool busy = false;
  int days = 7, generation = 0;
  DateTimeRange? custom;
  @override
  void initState() {
    super.initState();
    if (widget.active) load();
  }

  @override
  void didUpdateWidget(covariant AnalyticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) load();
  }

  DateTime get today {
    final seconds = widget.args.service.serverNow;
    final time = seconds > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            (seconds * 1000).round(),
            isUtc: true,
          )
        : DateTime.now().toUtc();
    final local = time.add(const Duration(hours: 7));
    return DateTime(local.year, local.month, local.day);
  }

  String date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Future<void> load() async {
    final request = ++generation;
    final s = widget.args.service;
    final token = s.token;
    if (!s.admin) return;
    final end = custom?.end ?? today,
        start = custom?.start ?? today.subtract(Duration(days: days - 1));
    setState(() {
      busy = true;
      error = null;
      data = null;
    });
    try {
      final r = await s.repository.request(
        'GET',
        '/api/admin/analytics?from=${date(start)}&to=${date(end)}',
        token: token,
      );
      if (mounted && request == generation && token == s.token) {
        setState(() => data = r);
      }
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && request == generation) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> pick() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: custom,
      helpText: 'Pilih periode (maksimal 366 hari)',
    );
    if (!mounted || result == null) return;
    if (result.end.difference(result.start).inDays >= 366) {
      showMessage(context, 'Pilih maksimal 366 hari.', error: true);
      return;
    }
    custom = result;
    await load();
  }

  List<Json> rows(String key) => (data?[key] as List? ?? []).cast<Json>();
  String number(dynamic value, {String suffix = ''}) => value is num
      ? '${value.toStringAsFixed(1).replaceAll('.', ',')}$suffix'
      : '—';
  Widget card(String title, Widget content, {String? note}) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          content,
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                note,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    ),
  );
  Widget metric(String label, String value, String detail) => SizedBox(
    width: 245,
    child: SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
  Widget bars(
    List<Json> values,
    String label,
    String value, {
    bool percent = false,
  }) => AnalysisBars(
    labels: values.map((r) => '${r[label]}').toList(),
    values: values.map((r) => (r[value] as num?)?.toDouble()).toList(),
    percent: percent,
  );
  Widget heatmap() {
    final items = rows('heatmap');
    const labels = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 42),
              ...List.generate(
                24,
                (h) => SizedBox(
                  width: 28,
                  child: Text(
                    '$h',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
          ...List.generate(
            7,
            (d) => Row(
              children: [
                SizedBox(width: 42, child: Text(labels[d])),
                ...List.generate(24, (h) {
                  final matches = items.where(
                    (r) => r['day'] == d && r['hour'] == h,
                  );
                  final value = matches.isEmpty
                      ? null
                      : matches.first['occupancy_pct'] as num?;
                  final description =
                      '${labels[d]} $h.00 WIB: ${number(value, suffix: '%')}';
                  return Tooltip(
                    message: description,
                    triggerMode: TooltipTriggerMode.tap,
                    child: Semantics(
                      label: description,
                      child: Container(
                        width: 26,
                        height: 26,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: value == null
                              ? AppColors.border
                              : AppColors.primary.withValues(
                                  alpha:
                                      0.06 + 0.94 * (value / 100).clamp(0, 1),
                                ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Abu-abu: belum ada pengamatan · Hijau makin pekat: makin terisi',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final busiest = d?['busiest'] as Json?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading(
          'Analisis Parkir',
          'Pola penggunaan area berdasarkan transaksi yang tercatat.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final n in [7, 30, 90])
              ChoiceChip(
                label: Text('$n hari'),
                selected: custom == null && days == n,
                onSelected: busy
                    ? null
                    : (_) {
                        custom = null;
                        days = n;
                        load();
                      },
              ),
            OutlinedButton.icon(
              onPressed: busy ? null : pick,
              icon: const Icon(Icons.date_range),
              label: const Text('Pilih tanggal'),
            ),
            IconButton(
              tooltip: 'Muat ulang analisis',
              onPressed: busy ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          SurfaceCard(
            child: Text(
              error!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        if (d != null) ...[
          Text(
            '${d['from_date']} — ${d['to_date']} · WIB',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Diperbarui ${wib(d['server_time'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              metric(
                'Kendaraan masuk',
                '${d['arrivals']}',
                'Sesi dengan waktu masuk dalam periode',
              ),
              metric(
                'Rata-rata durasi',
                number(d['mean_minutes'], suffix: ' menit'),
                '${d['completed_count']} sesi selesai',
              ),
              metric(
                'Median durasi',
                number(d['median_minutes'], suffix: ' menit'),
                '${d['excluded_active_count']} sesi belum selesai dikecualikan',
              ),
              metric(
                'Rata-rata keterisian',
                number(d['occupancy_pct'], suffix: '%'),
                'Puncak ${d['peak_occupied']} kendaraan sekaligus',
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (d['arrivals'] == 0)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Belum ada kendaraan masuk pada periode ini. Keterisian dapat berasal dari kendaraan yang masuk sebelumnya.',
              ),
            ),
          card(
            'Kendaraan masuk menurut jam',
            bars(rows('hourly'), 'hour', 'arrivals'),
            note:
                'Jumlah kedatangan pada tiap jam (00–23 WIB), digabung selama periode. Geser grafik untuk melihat seluruh jam.',
          ),
          card(
            'Kendaraan masuk menurut tanggal',
            bars(
              rows('daily')
                  .map(
                    (r) => {...r, 'label': (r['date'] as String).substring(5)},
                  )
                  .toList(),
              'label',
              'arrivals',
            ),
            note:
                'Sumbu tanggal: bulan-hari. Jumlah sesi masuk, bukan jumlah nopol unik.',
          ),
          card(
            'Kendaraan masuk menurut hari',
            bars(rows('weekdays'), 'label', 'arrivals'),
            note: 'Total kedatangan setiap nama hari dalam periode.',
          ),
          card(
            'Penggunaan mobil dan motor',
            AnalysisBars(
              labels: const ['Mobil', 'Motor'],
              values: [
                (d['vehicles']['MOBIL'] as num).toDouble(),
                (d['vehicles']['MOTOR'] as num).toDouble(),
              ],
            ),
            note:
                'Perbandingan jumlah sesi masuk, bukan durasi atau luas kendaraan.',
          ),
          card(
            'Pembayaran QR dan manual',
            AnalysisBars(
              labels: const ['QR', 'Manual'],
              values: [
                (d['payments']['QR_SIMULASI']['count'] as num).toDouble(),
                (d['payments']['MANUAL']['count'] as num).toDouble(),
              ],
            ),
            note:
                'Jumlah tagihan lunas berdasarkan waktu pembayaran; penalti dihitung sebagai tagihan terpisah. QR ${money((d['payments']['QR_SIMULASI']['amount'] as num).toInt())} · Manual ${money((d['payments']['MANUAL']['amount'] as num).toInt())}.',
          ),
          card(
            'Keterisian area menurut waktu',
            bars(
              rows('daily')
                  .map(
                    (r) => {...r, 'label': (r['date'] as String).substring(5)},
                  )
                  .toList(),
              'label',
              'occupancy_pct',
              percent: true,
            ),
            note:
                'Rata-rata persentase keterisian berbobot waktu. Kendaraan dihitung sampai benar-benar keluar, termasuk yang sudah membayar. — berarti belum ada waktu pengamatan.',
          ),
          card(
            'Hari dan jam paling terisi',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  busiest == null
                      ? 'Belum ada keterisian untuk dibandingkan.'
                      : '${busiest['label']} pukul ${busiest['hour']}.00–${(busiest['hour'] as int) + 1}.00 WIB · ${number(busiest['occupancy_pct'], suffix: '%')}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                heatmap(),
              ],
            ),
            note:
                'Perbandingan rata-rata keterisian per kombinasi hari dan jam yang teramati. Jika seri, ditampilkan yang lebih awal dalam urutan Senin–Minggu. Ini ringkasan historis, bukan prediksi.',
          ),
          const Text(
            'Durasi memakai sesi yang masuk pada periode terpilih dan sudah selesai saat laporan dibuka, termasuk yang keluar setelah akhir periode. Sesi aktif tidak masuk rata-rata/median. Hari ini dihitung sampai waktu pembaruan. Pengamatan dimulai sejak data sistem tersedia.',
            style: TextStyle(color: AppColors.muted, height: 1.6, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Scrollable bars with numeric labels, using the existing theme.
class AnalysisBars extends StatelessWidget {
  const AnalysisBars({
    super.key,
    required this.labels,
    required this.values,
    this.percent = false,
  });
  final List<String> labels;
  final List<double?> values;
  final bool percent;
  @override
  Widget build(BuildContext context) {
    final maximum = percent
        ? 100.0
        : values.fold<double>(1, (a, b) => math.max(a, b ?? 0));
    return LayoutBuilder(
      builder: (context, bounds) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(bounds.maxWidth, labels.length * 64.0),
          height: 220,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(labels.length, (i) {
              final v = values[i];
              final valueText = v == null
                  ? '—'
                  : percent
                  ? '${v.toStringAsFixed(1)}%'
                  : v.toStringAsFixed(0);
              return Expanded(
                child: Semantics(
                  label: '${labels[i]}: $valueText',
                  child: Tooltip(
                    message: '${labels[i]}: $valueText',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            valueText,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 150 * ((v ?? 0) / maximum).clamp(0, 1),
                            width: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 30,
                            child: Text(
                              labels[i],
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
