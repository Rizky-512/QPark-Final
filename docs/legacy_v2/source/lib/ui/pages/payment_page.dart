import 'package:flutter/material.dart';
import '../../domain/errors.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../common.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key, required this.args});
  final ScreenArgs args;
  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final search = TextEditingController(), cash = TextEditingController();
  late Future<List<Visit>> future;
  Quote? quote;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    future = widget.args.service.active(widget.args.session);
  }

  @override
  void dispose() {
    search.dispose();
    cash.dispose();
    super.dispose();
  }

  void reload() {
    final next = widget.args.service.active(widget.args.session, search.text);
    setState(() {
      future = next;
    });
  }

  Future<void> select(Visit visit) async {
    if (busy) return;
    if (quote != null &&
        cash.text.isNotEmpty &&
        !await confirm(
          context,
          title: 'Ganti kendaraan?',
          body: 'Isian pembayaran saat ini akan dibuang.',
          action: 'Ganti kendaraan',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    widget.args.busy(true);
    try {
      final result = await widget.args.service.quote(
        widget.args.session,
        visit.id,
      );
      if (mounted) {
        setState(() {
          quote = result;
          cash.clear();
        });
        widget.args.dirty(true);
      }
    } catch (e) {
      if (mounted) widget.args.error(context, e);
    } finally {
      widget.args.busy(false);
      if (mounted) setState(() => busy = false);
    }
  }

  String get changeLabel {
    if (quote == null || cash.text.trim().isEmpty) {
      return 'Masukkan uang diterima';
    }
    try {
      final change = parseRupiah(cash.text) - quote!.total;
      return change < 0 ? 'Kurang ${money(-change)}' : money(change);
    } on QParkException {
      return 'Format rupiah belum valid';
    }
  }

  Future<void> pay() async {
    if (busy || quote == null) return;
    setState(() => busy = true);
    widget.args.busy(true);
    try {
      final received = parseRupiah(cash.text);
      if (received < quote!.total) {
        throw const QParkException(
          'Uang diterima belum mencukupi total biaya.',
        );
      }
      final agreed = await confirm(
        context,
        title: 'Konfirmasi pembayaran',
        body:
            '${quote!.visit.plate}\nTotal: ${money(quote!.total)}\nTunai: ${money(received)}\nKembalian: ${money(received - quote!.total)}\n\nTransaksi yang lunas tidak dapat diubah.',
        action: 'Bayar sekarang',
      );
      if (!agreed || !mounted) return;
      final receipt = await widget.args.service.pay(
        widget.args.session,
        quote!.visit.id,
        cash.text,
        quote!.total,
      );
      if (!mounted) return;
      setState(() {
        quote = null;
        cash.clear();
      });
      widget.args.dirty(false);
      reload();
      await showReceipt(context, receipt);
    } on PriceChanged catch (e) {
      if (mounted) {
        setState(() => quote = e.quote);
        showMessage(context, e.message, error: true);
      }
    } catch (e) {
      if (mounted) widget.args.error(context, e);
    } finally {
      widget.args.busy(false);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel() async {
    if (busy) return;
    final agreed = await confirm(
      context,
      title: 'Batalkan isian pembayaran?',
      body: 'Kendaraan tetap aktif dan slot tetap terisi.',
      action: 'Buang isian',
    );
    if (agreed && mounted) {
      setState(() {
        quote = null;
        cash.clear();
      });
      widget.args.dirty(false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PageHeading(
        'Pembayaran',
        'Pilih kendaraan, periksa biaya, lalu terima tunai.',
      ),
      if (quote != null) ...[
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    vehicleIcon(quote!.visit.vehicle),
                    color: AppColors.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      quote!.visit.plate,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const StatusPill('Belum bayar'),
                ],
              ),
              const SizedBox(height: 16),
              DetailLine('ID transaksi', quote!.visit.id),
              DetailLine('Waktu masuk', dateTimeText(quote!.visit.enteredAt)),
              DetailLine(
                'Estimasi waktu keluar',
                dateTimeText(quote!.exitedAt),
              ),
              DetailLine('Durasi aktual', durationText(quote!.duration)),
              DetailLine(
                'Tarif saat masuk',
                '${money(quote!.visit.hourlyRate)}/jam',
              ),
              DetailLine('Jam tertagih', '${quote!.hours} jam'),
              const Divider(),
              DetailLine('Total biaya', money(quote!.total), emphasis: true),
              const SizedBox(height: 16),
              TextField(
                key: const Key('payment-cash'),
                controller: cash,
                enabled: !busy,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => pay(),
                decoration: const InputDecoration(
                  labelText: 'Uang diterima',
                  hintText: 'Contoh: 10.000',
                  prefixText: 'Rp ',
                ),
              ),
              const SizedBox(height: 8),
              DetailLine('Kembalian', changeLabel, emphasis: true),
              const SizedBox(height: 12),
              const Text(
                'Biaya dihitung ulang saat pembayaran dikonfirmasi.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    key: const Key('payment-confirm'),
                    onPressed: busy ? null : pay,
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(busy ? 'Memproses…' : 'Konfirmasi pembayaran'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : cancel,
                    child: const Text('Batalkan isian'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: search,
              enabled: !busy,
              onSubmitted: (_) => reload(),
              decoration: InputDecoration(
                labelText: 'Cari pelat atau ID transaksi',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Cari transaksi aktif',
                  onPressed: busy ? null : reload,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
            const SizedBox(height: 16),
            LoadPanel(
              future: future,
              retry: reload,
              onExpired: widget.args.expire,
              builder: (visits) =>
                  VisitList(visits: visits, action: 'Pilih', onSelect: select),
            ),
          ],
        ),
      ),
    ],
  );
}
