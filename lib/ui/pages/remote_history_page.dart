import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/remote_repository.dart';
import '../common.dart';
import '../remote_common.dart';

class RemoteHistoryPage extends StatefulWidget {
  const RemoteHistoryPage({
    super.key,
    required this.args,
    required this.active,
  });
  final RemoteArgs args;
  final bool active;
  @override
  State<RemoteHistoryPage> createState() => _RemoteHistoryPageState();
}

class _RemoteHistoryPageState extends State<RemoteHistoryPage> {
  List<Json> rows = [];
  final search = TextEditingController();
  String vehicle = '', method = '';
  DateTime? from, to;
  int offset = 0, total = 0, revenue = 0, requestId = 0;
  bool busy = false;
  String? error, scope;
  Timer? timer;
  String get currentScope =>
      '${widget.args.service.operationOwner}:${widget.args.service.selected}';
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (widget.active &&
          widget.args.service.foreground &&
          widget.args.service.online &&
          !busy) {
        load();
      }
    });
  }

  @override
  void didUpdateWidget(covariant RemoteHistoryPage old) {
    super.didUpdateWidget(old);
    if (widget.active && (!old.active || scope != currentScope)) {
      offset = 0;
      load();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  String date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Future<void> load() async {
    final s = widget.args.service;
    final id = ++requestId;
    final nextScope = currentScope;
    if (!s.officer && s.selected == null) {
      setState(() {
        rows = [];
        total = 0;
        revenue = 0;
        scope = nextScope;
        error = null;
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
      if (scope != nextScope) rows = [];
      scope = nextScope;
    });
    final params = {
      'offset': '$offset',
      if (s.officer) 'q': search.text else 'plate': s.selected!,
      if (vehicle.isNotEmpty) 'vehicle': vehicle,
      if (method.isNotEmpty) 'method': method,
      if (from != null) 'from': date(from!),
      if (to != null) 'to': date(to!),
    };
    final url = Uri(
      path: s.officer ? '/api/officer/history' : '/api/history',
      queryParameters: params,
    ).toString();
    try {
      final r = await s.repository.request('GET', url, token: s.token);
      if (mounted && id == requestId && nextScope == currentScope) {
        setState(() {
          rows = (r['sessions'] as List? ?? []).cast<Json>();
          total = (r['total'] as num? ?? 0).toInt();
          revenue = (r['revenue'] as num? ?? 0).toInt();
        });
      }
    } catch (e) {
      if (mounted && id == requestId) setState(() => error = e.toString());
    } finally {
      if (mounted && id == requestId) setState(() => busy = false);
    }
  }

  Future<void> pick(bool start) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (start ? from : to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) {
      setState(() {
        if (start) {
          from = d;
        } else {
          to = d;
        }
        offset = 0;
      });
      await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.args.service;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          'Riwayat parkir',
          service.officer
              ? 'Catatan kendaraan dan pembayaran QR maupun manual.'
              : 'Riwayat nopol ${service.selected ?? 'belum dipilih'}. Pilih kendaraan pada Beranda.',
          action: IconButton(
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang riwayat',
          ),
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (service.officer)
                TextField(
                  controller: search,
                  onSubmitted: (_) {
                    offset = 0;
                    load();
                  },
                  decoration: InputDecoration(
                    labelText: 'Cari nopol riwayat',
                    suffixIcon: IconButton(
                      onPressed: () {
                        offset = 0;
                        load();
                      },
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: vehicle,
                      decoration: const InputDecoration(
                        labelText: 'Jenis kendaraan',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '',
                          child: Text('Semua kendaraan'),
                        ),
                        DropdownMenuItem(value: 'MOBIL', child: Text('Mobil')),
                        DropdownMenuItem(value: 'MOTOR', child: Text('Motor')),
                      ],
                      onChanged: (v) {
                        setState(() => vehicle = v!);
                        offset = 0;
                        load();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: method,
                      decoration: const InputDecoration(
                        labelText: 'Pembayaran',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '',
                          child: Text('Semua metode'),
                        ),
                        DropdownMenuItem(
                          value: 'QR_SIMULASI',
                          child: Text('QR simulasi'),
                        ),
                        DropdownMenuItem(
                          value: 'MANUAL',
                          child: Text('Manual'),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => method = v!);
                        offset = 0;
                        load();
                      },
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => pick(true),
                    child: Text(from == null ? 'Tanggal mulai' : date(from!)),
                  ),
                  OutlinedButton(
                    onPressed: () => pick(false),
                    child: Text(to == null ? 'Tanggal akhir' : date(to!)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        from = null;
                        to = null;
                        offset = 0;
                      });
                      load();
                    },
                    child: const Text('Hapus tanggal'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '$total sesi · Total pembayaran ${money(revenue)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Filter tanggal mengikuti waktu masuk kendaraan (WIB).',
              ),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Text(error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty && !busy)
          const EmptyState(
            title: 'Belum ada riwayat',
            description:
                'Riwayat akan muncul setelah kendaraan dicatat, atau ubah filter pencarian.',
          ),
        ...rows.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SessionSummary(s),
                  const Divider(),
                  ...(s['invoices'] as List)
                      .cast<Json>()
                      .where((i) => i['state'] == 'PAID')
                      .map(
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${i['kind'] == 'PENALTY' ? 'Tambahan' : 'Parkir'} · ${i['payment_method'] == 'MANUAL' ? 'Manual' : 'QR simulasi'} · ${money((i['amount'] as num).toInt())}\nDibayar: ${wib(i['paid_at'])}${i['received'] == null ? '' : ' · Diterima ${money((i['received'] as num).toInt())} · Kembalian ${money((i['change_amount'] as num).toInt())}'}',
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: offset == 0 || busy
                  ? null
                  : () {
                      offset = (offset - 50).clamp(0, total);
                      load();
                    },
              child: const Text('Sebelumnya'),
            ),
            TextButton(
              onPressed: offset + 50 >= total || busy
                  ? null
                  : () {
                      offset += 50;
                      load();
                    },
              child: const Text('Berikutnya'),
            ),
          ],
        ),
      ],
    );
  }
}
