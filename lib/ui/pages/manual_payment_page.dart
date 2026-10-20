import 'package:flutter/material.dart';
import '../../data/remote_repository.dart';
import '../common.dart';
import '../remote_common.dart';

class ManualPaymentPage extends StatefulWidget {
  const ManualPaymentPage({super.key, required this.args});
  final RemoteArgs args;
  @override
  State<ManualPaymentPage> createState() => _ManualPaymentPageState();
}

class _ManualPaymentPageState extends State<ManualPaymentPage> {
  final received = TextEditingController(), plate = TextEditingController();
  String? selected;
  Json? session, invoice;
  bool busy = false, verified = false;
  @override
  void dispose() {
    received.dispose();
    plate.dispose();
    super.dispose();
  }

  Future<void> quote() async {
    if (selected == null || busy) return;
    setState(() {
      busy = true;
      invoice = null;
      session = null;
      verified = false;
      received.clear();
      plate.clear();
    });
    try {
      final r = await widget.args.service.post('/api/officer/manual-quote', {
        'session_id': selected,
      });
      if (mounted) {
        setState(() {
          session = r['session'] as Json;
          invoice = r['invoice'] as Json?;
        });
      }
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pay() async {
    final s = session;
    if (s == null || busy || !verified) return;
    final due = (invoice?['amount'] as num? ?? 0).toInt();
    final cash = due == 0 ? 0 : int.tryParse(received.text);
    if (cash == null || cash < due) {
      showMessage(
        context,
        'Isi uang diterima dengan angka utuh minimal sebesar tagihan.',
        error: true,
      );
      return;
    }
    if (!await confirm(
      context,
      title: due == 0
          ? 'Izinkan kendaraan keluar?'
          : 'Konfirmasi pembayaran manual?',
      body: due == 0
          ? 'Tagihan telah lunas. Cocokkan kendaraan sebelum memberi izin.'
          : 'Tagihan ${money(due)}. Uang diterima ${money(cash)}. Kembalian ${money(cash - due)}. Konfirmasi setelah uang benar-benar diterima.',
      action: 'Konfirmasi & izinkan',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final r = await widget.args.service.post('/api/officer/manual-pay', {
        'session_id': s['id'],
        'invoice_id': invoice?['id'],
        'expected_amount': due,
        'received': cash,
        'plate': plate.text,
        'verified': verified,
      }, idempotent: true);
      if (mounted) {
        setState(() {
          session = r['session'] as Json;
          invoice = null;
        });
        showMessage(
          context,
          'Izin keluar diberikan. Konfirmasi setelah kendaraan lewat.',
        );
      }
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> finish(bool passed) async {
    final s = session;
    if (s == null || busy || s['authorization'] == null) return;
    if (passed &&
        !await confirm(
          context,
          title: 'Kendaraan sudah lewat?',
          body: 'Kapasitas dikembalikan setelah kendaraan benar-benar keluar.',
          action: 'Ya, sudah keluar',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final r = await widget.args.service
          .post('/api/officer/${passed ? 'complete' : 'cancel'}', {
            'session_id': s['id'],
            'authorization_id': s['authorization']['id'],
            'passed': passed,
          }, idempotent: true);
      if (mounted) {
        setState(() {
          session = r['session'] as Json;
          verified = false;
        });
      }
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.args.service;
    final live = service.sessions.where((x) => x['id'] == session?['id']);
    final s = live.isNotEmpty ? live.first : session;
    final authorized =
        s?['state'] == 'EXIT_AUTHORIZED' && s?['authorization'] != null;
    final completed = s?['state'] == 'COMPLETED';
    final due = (invoice?['amount'] as num? ?? 0).toInt();
    final cash = int.tryParse(received.text);
    final validSelection = service.sessions.any((x) => x['id'] == selected)
        ? selected
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading(
          'Pembayaran manual',
          'Pilih kendaraan, terima pembayaran, lalu konfirmasi kendaraan keluar.',
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('manual-$validSelection'),
                initialValue: validSelection,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kendaraan aktif'),
                items: service.sessions
                    .map(
                      (x) => DropdownMenuItem(
                        value: x['id'] as String,
                        child: Text(
                          '${x['plate']} · ${x['vehicle_type'] == 'MOTOR' ? 'Motor' : 'Mobil'}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        selected = v;
                        session = null;
                        invoice = null;
                        verified = false;
                      }),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy || !service.online || selected == null
                    ? null
                    : quote,
                icon: const Icon(Icons.receipt_long),
                label: const Text('Muat tagihan manual'),
              ),
              if (s != null) ...[
                const SizedBox(height: 20),
                SessionSummary(s),
                const SizedBox(height: 20),
                if (completed)
                  const Text(
                    'Pembayaran dan sesi selesai. Kendaraan sudah keluar.',
                  )
                else if (authorized) ...[
                  Text(
                    'Gerbang simulasi terbuka. Izin sampai ${wib(s['authorization']['expires_at'])}.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy || !service.online
                        ? null
                        : () => finish(true),
                    child: const Text('Kendaraan sudah keluar'),
                  ),
                  TextButton(
                    onPressed: busy || !service.online
                        ? null
                        : () => finish(false),
                    child: const Text('Batal izin · kendaraan belum lewat'),
                  ),
                ] else ...[
                  Text(
                    'Tagihan saat ini: ${money(due)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (invoice?['expires_at'] != null)
                    Text(
                      'Berlaku sampai ${wib(invoice!['expires_at'])}. Muat ulang jika kedaluwarsa.',
                    ),
                  if (due == 0)
                    const Text(
                      'Tidak ada pembayaran baru. Tagihan sudah lunas.',
                    ),
                  if (due > 0) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: received,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Uang diterima (Rp)',
                        hintText: 'Contoh: 10000',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Kembalian: ${cash != null && cash >= due ? money(cash - due) : '—'}',
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: plate,
                    onChanged: (_) => setState(() => verified = false),
                    decoration: const InputDecoration(
                      labelText: 'Nopol kendaraan di depan petugas',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: verified,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => verified = v!),
                    title: const Text(
                      'Kendaraan dan nopol cocok; pembayaran sudah diterima atau tagihan telah lunas',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: busy || !service.online || !verified
                        ? null
                        : pay,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      due == 0
                          ? 'Izinkan keluar tanpa tagihan baru'
                          : 'Bayar manual & izinkan keluar',
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
