import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../data/remote_repository.dart';
import '../common.dart';
import '../remote_common.dart';
import 'manual_payment_page.dart';

class ExitPage extends StatefulWidget {
  const ExitPage({super.key, required this.args});
  final RemoteArgs args;
  @override
  State<ExitPage> createState() => _ExitPageState();
}

class _ExitPageState extends State<ExitPage>
    with AutomaticKeepAliveClientMixin {
  final token = TextEditingController(), plate = TextEditingController();
  final tokenScroll = ScrollController(keepScrollOffset: false);
  Json? scanned;
  String? scannedToken;
  bool matched = false, busy = false, manual = false;
  Timer? ticker;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    token.dispose();
    tokenScroll.dispose();
    plate.dispose();
    ticker?.cancel();
    super.dispose();
  }

  Future<void> camera() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ScannerPage()),
    );
    if (value != null && mounted) {
      token.text = value;
      await scan();
    }
  }

  Future<void> scan() async {
    if (busy) return;
    setState(() {
      busy = true;
      scanned = null;
      scannedToken = null;
      matched = false;
      plate.clear();
    });
    try {
      final value = token.text.trim();
      final r = await widget.args.service.post('/api/officer/scan', {
        'qr': value,
      });
      if (mounted) {
        setState(() {
          scanned = r['session'] as Json;
          scannedToken = value;
        });
      }
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Json? get live {
    if (scanned == null) return null;
    final current = widget.args.service.sessions.where(
      (s) => s['id'] == scanned!['id'],
    );
    return current.isEmpty ? scanned : current.first;
  }

  Future<void> authorize() async {
    if (busy || !matched) return;
    setState(() => busy = true);
    try {
      final r = await widget.args.service.post('/api/officer/authorize', {
        'qr': scannedToken,
        'plate': plate.text,
        'verified': matched,
      }, idempotent: true);
      if (mounted) {
        setState(() => scanned = r['session'] as Json);
        showMessage(
          context,
          'Gerbang simulasi terbuka. Konfirmasi setelah kendaraan lewat.',
        );
      }
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> finish(bool complete) async {
    final s = live;
    if (s == null || s['authorization'] == null || busy) return;
    if (complete &&
        !await confirm(
          context,
          title: 'Kendaraan sudah lewat?',
          body:
              'Konfirmasi hanya setelah kendaraan benar-benar meninggalkan area.',
          action: 'Ya, sudah keluar',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final r = await widget.args.service
          .post('/api/officer/${complete ? 'complete' : 'cancel'}', {
            'session_id': s['id'],
            'authorization_id': s['authorization']['id'],
            'passed': complete,
          }, idempotent: true);
      if (mounted) {
        setState(() => scanned = r['session'] as Json);
        showMessage(
          context,
          complete
              ? 'Sesi selesai. Kapasitas sudah diperbarui.'
              : 'Izin dibatalkan. Kendaraan tetap tercatat di dalam.',
        );
      }
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final service = widget.args.service, s = live;
    final authorized =
        s?['state'] == 'EXIT_AUTHORIZED' &&
        s?['authorization'] != null &&
        service.serverNow < (s!['authorization']['expires_at'] as num);
    final qrContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading(
          'Verifikasi keluar',
          'Pindai QR keluar lalu cocokkan dengan kendaraan di pintu keluar.',
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                key: const Key('scan-camera'),
                onPressed: busy || !service.online ? null : camera,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Pindai QR dengan kamera'),
              ),
              const SizedBox(height: 20),
              ExpansionTile(
                key: const PageStorageKey('exit-token-help'),
                tilePadding: EdgeInsets.zero,
                title: const Text('Kamera tidak tersedia?'),
                subtitle: const Text('Gunakan token QR untuk bantuan demo.'),
                children: [
                  TextField(
                    key: const Key('exit-token'),
                    controller: token,
                    scrollController: tokenScroll,
                    enabled: !busy,
                    onChanged: (_) => setState(() {
                      scanned = null;
                      scannedToken = null;
                      matched = false;
                    }),
                    decoration: const InputDecoration(
                      labelText: 'Token manual · bantuan demonstrasi',
                      helperText:
                          'Tempel token QR keluar jika kamera tidak tersedia.',
                      helperMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('exit-scan'),
                    onPressed: busy || !service.online ? null : scan,
                    icon: const Icon(Icons.search),
                    label: Text(busy ? 'Memeriksa…' : 'Periksa QR / token'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (s != null) ...[
          const SizedBox(height: 24),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SessionSummary(s),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: authorized
                        ? AppColors.successBackground
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Icon(
                        authorized ? Icons.lock_open : Icons.lock_outline,
                        color: AppColors.primary,
                      ),
                      Text(
                        authorized
                            ? 'Gerbang simulasi: TERBUKA'
                            : 'Gerbang simulasi: TERTUTUP',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (authorized) ...[
                  Text(
                    'Sisa persetujuan: ${remaining(s['authorization']['expires_at'], service.serverNow)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Kapasitas tetap terpakai sampai kendaraan dikonfirmasi lewat.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('exit-complete'),
                    onPressed: busy || !service.online
                        ? null
                        : () => finish(true),
                    child: const Text('Kendaraan sudah keluar'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: busy || !service.online
                        ? null
                        : () => finish(false),
                    child: const Text('Batal izin · kendaraan belum lewat'),
                  ),
                ] else if (s['state'] != 'COMPLETED') ...[
                  TextField(
                    key: const Key('exit-plate'),
                    controller: plate,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() => matched = false),
                    decoration: const InputDecoration(
                      labelText: 'Nopol kendaraan di depan petugas',
                      helperText:
                          'Ketik dari kendaraan fisik; harus sama dengan tiket.',
                      helperMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    key: const Key('exit-match'),
                    contentPadding: EdgeInsets.zero,
                    value: matched,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => matched = v!),
                    title: const Text(
                      'Saya telah mencocokkan nopol tiket dengan kendaraan',
                    ),
                  ),
                  FilledButton(
                    key: const Key('exit-authorize'),
                    onPressed:
                        busy ||
                            !matched ||
                            !service.online ||
                            scannedToken == null
                        ? null
                        : authorize,
                    child: const Text('Izinkan keluar'),
                  ),
                ] else
                  const Text('Sesi selesai. Pindai QR kendaraan berikutnya.'),
              ],
            ),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('QR keluar'),
              icon: Icon(Icons.qr_code_scanner),
            ),
            ButtonSegment(
              value: true,
              label: Text('Bayar manual'),
              icon: Icon(Icons.payments_outlined),
            ),
          ],
          selected: {manual},
          onSelectionChanged: (v) => setState(() => manual = v.first),
        ),
        const SizedBox(height: 24),
        Offstage(offstage: manual, child: qrContent),
        Offstage(
          offstage: !manual,
          child: ManualPaymentPage(args: widget.args),
        ),
      ],
    );
  }
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();
  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  bool accepted = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pindai QR keluar')),
    body: MobileScanner(
      onDetect: (capture) {
        if (accepted) return;
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null && value.isNotEmpty) {
            accepted = true;
            Navigator.pop(context, value);
            break;
          }
        }
      },
      errorBuilder: (context, error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Kamera tidak tersedia. Izinkan kamera dan gunakan HTTPS atau localhost. Token manual tersedia untuk demonstrasi.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kembali'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
