import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../data/remote_repository.dart';
import '../../config.dart';
import '../common.dart';
import '../remote_common.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key, required this.args});
  final RemoteArgs args;
  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  bool ready = false, busy = false;
  String? sessionId, invoiceId;
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  Future<void> invoice() async {
    final ticket = widget.args.service.ticket;
    if (ticket == null) return;
    setState(() => busy = true);
    try {
      final r = await widget.args.service.post('/api/invoice', {
        'session_id': ticket['id'],
      });
      if (mounted) {
        setState(() => invoiceId = (r['invoice'] as Json?)?['id'] as String?);
      }
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pay(Json invoice, String outcome) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await widget.args.service.post('/api/payment', {
        'invoice_id': invoice['id'],
        'outcome': outcome,
      }, idempotent: true);
      if (!mounted) return;
      showMessage(
        context,
        r['outcome'] == 'SUCCESS'
            ? 'Pembayaran simulasi berhasil. Waktu keluar 15 menit sudah dimulai.'
            : r['outcome'] == 'FAILED'
            ? 'Pembayaran simulasi gagal. Belum ada izin keluar.'
            : 'Pembayaran masih menunggu.',
        error: r['outcome'] == 'FAILED',
      );
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget qr(String value) => Center(
    child: Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: QrImageView(
        data: value,
        size: (MediaQuery.sizeOf(context).width - 112).clamp(140.0, 210.0),
        gapless: true,
        backgroundColor: Colors.white,
        semanticsLabel: 'Kode QR QPark',
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final service = widget.args.service, s = service.ticket;
    if (sessionId != s?['id']) {
      sessionId = s?['id'] as String?;
      invoiceId = null;
      ready = false;
    }
    if (s == null) {
      return Column(
        children: [
          const PageHeading(
            'Tiket & pembayaran',
            'Pilih nopol yang telah dicatat petugas.',
          ),
          const SurfaceCard(
            child: EmptyState(
              title: 'Belum ada tiket aktif',
              description:
                  'Simpan dan pilih nopol pada Beranda. Tiket muncul setelah kendaraan masuk diverifikasi.',
            ),
          ),
          FilledButton.icon(
            onPressed: () => widget.args.navigate(0),
            icon: const Icon(Icons.directions_car_outlined),
            label: const Text('Pilih kendaraan'),
          ),
        ],
      );
    }
    final invoices = (s['invoices'] as List).cast<Json>();
    final selected = invoices.where((i) => i['id'] == invoiceId);
    final current = selected.isEmpty ? null : selected.first;
    final window = s['window'] as Json?;
    final valid = s['window_status'] == 'VALID';
    final completed = s['state'] == 'COMPLETED';
    final pendingPenalty = invoices.any(
      (i) => i['kind'] == 'PENALTY' && i['state'] == 'PENDING',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading(
          'Tiket & pembayaran',
          'Pembayaran digital simulasi · tidak memindahkan uang sungguhan.',
        ),
        SurfaceCard(child: SessionSummary(s)),
        const SizedBox(height: 24),
        if (completed)
          const SurfaceCard(
            child: EmptyState(
              title: 'Kendaraan sudah keluar',
              description: 'Sesi selesai. QR sesi ini sudah dinonaktifkan.',
            ),
          )
        else if (valid && window != null)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'QR keluar',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  s['state'] == 'EXIT_AUTHORIZED'
                      ? 'Petugas sudah mengizinkan keluar. Tunggu konfirmasi kendaraan lewat.'
                      : 'Tunjukkan QR ini kepada petugas ketika kendaraan berhenti di pintu keluar.',
                ),
                const SizedBox(height: 16),
                if (service.online && s['exit_qr'] != null)
                  qr(s['exit_qr'] as String)
                else
                  const Text(
                    'Offline · QR disembunyikan sampai status server diperbarui.',
                  ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    s['state'] == 'EXIT_AUTHORIZED'
                        ? 'Persetujuan: ${remaining(s['authorization']['expires_at'], service.serverNow)}'
                        : 'Sisa waktu: ${remaining(window['deadline'], service.serverNow)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Batas keluar: ${wib(window['deadline'])}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Keputusan akhir diperiksa oleh server saat petugas mengizinkan keluar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
                if (s['exit_qr'] != null)
                  TextButton.icon(
                    onPressed: service.online
                        ? () async {
                            await Clipboard.setData(
                              ClipboardData(text: s['exit_qr'] as String),
                            );
                            if (context.mounted) {
                              showMessage(
                                context,
                                'Token disalin untuk bantuan demonstrasi.',
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.copy),
                    label: const Text('Salin token · bantuan demo'),
                  ),
              ],
            ),
          )
        else
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  pendingPenalty
                      ? 'Tambahan keterlambatan'
                      : 'Siap meninggalkan parkir?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  pendingPenalty
                      ? 'Batas keluar terlewati. Tambahan ${money((s['hourly_rate'] as num? ?? 7000).toInt())} berlaku satu kali untuk jendela ini. Setelah dibayar, tersedia 15 menit baru.'
                      : 'Tarif ${money((s['hourly_rate'] as num? ?? 7000).toInt())} per jam penuh, minimum satu jam. Sisa menit tidak dibulatkan ke atas.',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const Key('payment-ready'),
                  contentPadding: EdgeInsets.zero,
                  value: ready,
                  onChanged: busy ? null : (v) => setState(() => ready = v!),
                  title: const Text(
                    'Saya memastikan kendaraan siap keluar dalam 15 menit setelah pembayaran berhasil',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('invoice-open'),
                  onPressed: ready && !busy && service.online ? invoice : null,
                  icon: const Icon(Icons.qr_code_rounded),
                  label: Text(
                    busy ? 'Memproses…' : 'Buka tagihan & QR pembayaran',
                  ),
                ),
                if (current != null && ready) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    current['kind'] == 'PENALTY'
                        ? 'Tambahan keterlambatan'
                        : 'Tagihan dasar',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    money(current['amount'] as int),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  if (current['kind'] == 'BASE')
                    Text(
                      '${current['hours']} jam × ${money((s['hourly_rate'] as num? ?? 7000).toInt())} · snapshot ${durationText(Duration(seconds: (current['duration'] as num).toInt()))}',
                    ),
                  Text(
                    current['expires_at'] == null
                        ? 'Nominal tambahan tidak kedaluwarsa.'
                        : 'Berlaku sebelum: ${wib(current['expires_at'])}',
                  ),
                  const SizedBox(height: 12),
                  const StatusPill('QRIS simulasi · bukan QR merchant'),
                  const SizedBox(height: 12),
                  if (current['state'] == 'PENDING' &&
                      (current['expires_at'] == null ||
                          service.serverNow <
                              (current['expires_at'] as num))) ...[
                    qr('QPP.SIMULASI.${current['id']}'),
                    const SizedBox(height: 16),
                    const Text(
                      'Kontrol simulator untuk demonstrasi. Pilih hasil pembayaran:',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          key: const Key('payment-success'),
                          onPressed:
                              busy || !service.online || !AppConfig.simulation
                              ? null
                              : () => pay(current, 'SUCCESS'),
                          child: const Text('Simulasi berhasil'),
                        ),
                        ExpansionTile(
                          key: const PageStorageKey('payment-scenarios'),
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Skenario demo lainnya'),
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                OutlinedButton(
                                  onPressed:
                                      busy ||
                                          !service.online ||
                                          !AppConfig.simulation
                                      ? null
                                      : () => pay(current, 'FAILED'),
                                  child: const Text('Gagal'),
                                ),
                                OutlinedButton(
                                  onPressed:
                                      busy ||
                                          !service.online ||
                                          !AppConfig.simulation
                                      ? null
                                      : () => pay(current, 'PENDING'),
                                  child: const Text('Menunggu'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else
                    const Text(
                      'Tagihan tidak lagi berlaku. Buka tagihan baru atau periksa status terbaru.',
                      style: TextStyle(color: AppColors.danger),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
