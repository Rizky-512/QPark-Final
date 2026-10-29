import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../data/remote_repository.dart';
import '../../data/parking_forecast.dart';
import '../widgets/vehicle_pie.dart';
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
  bool busy = false, explaining = false;
  String? explanation, aiError;
  int days = 7, generation = 0;
  DateTimeRange? custom;
  ParkingForecast? forecast;
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
      forecast = null;
      explanation = null;
      aiError = null;
      explaining = false;
    });
    try {
      final r = await s.repository.request(
        'GET',
        '/api/admin/analytics?from=${date(start)}&to=${date(end)}',
        token: token,
      );
      if (mounted && request == generation && token == s.token) {
        setState(() {
          data = r;
          if (r['forecast'] is Map<String, dynamic>) {
            forecast = ParkingForecast(r['forecast'] as Json);
          }
        });
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
    final start = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDate: custom?.start ?? today.subtract(Duration(days: days - 1)),
      helpText: '1 dari 2: Pilih tanggal mulai',
    );
    if (!mounted || start == null) return;
    final limit = start.add(const Duration(days: 365));
    final last = limit.isBefore(today) ? limit : today;
    final previousEnd = custom?.end ?? today;
    final end = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: last,
      initialDate: previousEnd.isBefore(start)
          ? start
          : previousEnd.isAfter(last)
          ? last
          : previousEnd,
      helpText: '2 dari 2: Pilih tanggal akhir (maks. 366 hari)',
    );
    if (!mounted || end == null) return;
    custom = DateTimeRange(start: start, end: end);
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
  Future<void> explain() async {
    final f = forecast;
    final token = widget.args.service.token;
    if (f == null || token == null) return;
    final request = generation;
    setState(() {
      explaining = true;
      aiError = null;
    });
    try {
      final text = await widget.args.service.repository.explainForecast({
        'capacity': f.capacity,
        'current': f.current,
        'target_time': f.targetTime,
        'predicted': f.predicted,
        'probability': f.probability,
      }, token: token);
      if (mounted &&
          request == generation &&
          token == widget.args.service.token) {
        setState(() => explanation = text);
      }
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => aiError = e.toString());
      }
    } finally {
      if (mounted && request == generation) setState(() => explaining = false);
    }
  }

  Widget forecastCard() {
    final f = forecast;
    if (f == null) {
      return card(
        '30 menit lagi',
        const Text(
          'Prediksi belum tersedia. Pengelola perlu memperbarui layanan prediksi.',
        ),
      );
    }
    final probability = f.probability;
    final time = DateTime.fromMillisecondsSinceEpoch(
      (f.targetTime * 1000).round(),
      isUtc: true,
    ).add(const Duration(hours: 7));
    final clock =
        '${time.hour.toString().padLeft(2, '0')}.${time.minute.toString().padLeft(2, '0')} WIB';
    return card(
      'Bagaimana parkir 30 menit lagi?',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Perkiraan untuk pukul $clock',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 24,
            runSpacing: 20,
            children: [
              SizedBox(
                width: 280,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Kendaraan di area'),
                    Text(
                      f.predicted == null
                          ? 'Belum tersedia'
                          : 'Sekitar ${f.predicted!.round()} kendaraan',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'Sekarang ${f.current} · Kapasitas ${f.capacity} tempat',
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 280,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Peluang hampir penuh'),
                    Text(
                      probability == null
                          ? 'Masih belajar'
                          : '${(probability * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    if (probability != null) ...[
                      LinearProgressIndicator(
                        value: probability,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      'Artinya, peluang ${(.8 * f.capacity).ceil()} tempat atau lebih akan terisi.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(f.reason),
          if (f.predicted != null)
            AnalysisBars(
              labels: const ['Sekarang', '30 menit lagi'],
              values: [f.current.toDouble(), f.predicted],
            ),
          const SizedBox(height: 8),
          const Text(
            'Peluang hampir penuh berbeda dari persentase tempat terisi.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const Divider(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: explaining || explanation != null ? null : explain,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                explaining ? 'Menyiapkan penjelasan...' : 'Jelaskan dengan AI',
              ),
            ),
          ),
          const Text(
            'Gemini menjelaskan hasil model dalam bahasa sederhana.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (explanation != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(explanation!),
            ),
          if (aiError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                aiError!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Tentang model & hasil pengujian'),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Supervised learning: model belajar dari contoh riwayat yang sudah diketahui hasilnya. Regresi linear memprediksi jumlah kendaraan; regresi logistik memprediksi peluang minimal 80% tempat terisi. Gemini hanya menjelaskan hasil, tidak menentukan angka.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Masukan: jumlah kendaraan, masuk dan keluar 30 menit terakhir, jam, dan hari. Termasuk kendaraan baru yang akan masuk. Prediksi selalu dihitung dari waktu pembaruan, bukan tanggal laporan.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${f.samples} contoh · ${f.trainCount} latih · ${f.validationCount} validasi · ${f.testCount} uji. Data dibagi berurutan menurut waktu; label yang melintasi batas dibuang.',
                    ),
                    if (f.testMetrics.isNotEmpty) ...[
                      Text(
                        'Kesalahan jumlah pada data uji: ${number(f.testMetrics['mae'])} kendaraan (pembanding: ${number(f.testMetrics['baseline_mae'])}).',
                      ),
                      if (f.testMetrics['brier'] != null)
                        Text(
                          'Brier score peluang: ${f.testMetrics['brier']!.toStringAsFixed(3)} (pembanding: ${f.testMetrics['baseline_brier']!.toStringAsFixed(3)}). Lebih kecil lebih baik; bukan persentase akurasi.',
                        ),
                    ],
                    if (f.logisticReason != null) Text(f.logisticReason!),
                    const Text(
                      'Hasil hanya ditampilkan jika mengungguli pembanding pada validasi dan uji. Data yang tidak lengkap atau simulasi belum membuktikan akurasi di lapangan.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      note:
          'Perkiraan dari maksimal 8 minggu riwayat terakhir. Muat ulang untuk memperbarui.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading(
          'Analisis Parkir',
          'Lihat perkiraan kondisi parkir dan ringkasan kunjungan.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
            label: const Text('Muat ulang'),
          ),
        ),
        const SizedBox(height: 12),
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
            'Diperbarui ${wib(d['server_time'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          forecastCard(),
        ],
        const SizedBox(height: 8),
        Text(
          'Ringkasan kunjungan',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
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
          ],
        ),
        const SizedBox(height: 16),
        if (d != null) ...[
          Text(
            '${d['from_date']} – ${d['to_date']}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              metric(
                'Total kunjungan',
                '${d['arrivals']}',
                'Kendaraan masuk selama periode ini',
              ),
              metric(
                'Rata-rata lama parkir',
                number(d['mean_minutes'], suffix: ' menit'),
                'Dihitung dari kendaraan yang sudah keluar',
              ),
            ],
          ),
          const SizedBox(height: 20),
          card(
            'Lebih banyak motor atau mobil?',
            VehiclePie(
              cars: (d['vehicles']['MOBIL'] as num).toInt(),
              motors: (d['vehicles']['MOTOR'] as num).toInt(),
            ),
            note: 'Persentase dari seluruh kunjungan dalam periode terpilih.',
          ),
          card(
            'Jam kedatangan paling ramai',
            bars(rows('hourly'), 'hour', 'arrivals'),
            note:
                'Angka di atas batang menunjukkan jumlah kendaraan masuk. Jam dalam WIB; geser untuk melihat jam lainnya.',
          ),
          ExpansionTile(
            title: const Text('Lihat rincian kunjungan'),
            children: [
              card(
                'Kunjungan per tanggal',
                bars(
                  rows('daily')
                      .map(
                        (r) => {
                          ...r,
                          'label': (r['date'] as String).substring(5, 10),
                        },
                      )
                      .toList(),
                  'label',
                  'arrivals',
                ),
                note: 'Tanggal ditulis bulan-hari.',
              ),
              card(
                'Kunjungan per hari',
                bars(rows('weekdays'), 'label', 'arrivals'),
              ),
            ],
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
