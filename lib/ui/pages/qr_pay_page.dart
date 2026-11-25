import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../data/remote_repository.dart';
import '../../logic/remote_service.dart';
import '../common.dart';
import '../remote_common.dart';

/// Dedicated QR Pay screen launched from the center mobile FAB.
/// Scans a parking invoice QR (`QPP.SIMULASI.<id>` or `QPP.<id>`) and pays with E-Wallet.
class QrPayPage extends StatefulWidget {
  const QrPayPage({
    super.key,
    required this.service,
    required this.onOpenWallet,
    required this.onOpenActivity,
  });
  final RemoteService service;
  final VoidCallback onOpenWallet;
  final VoidCallback onOpenActivity;

  @override
  State<QrPayPage> createState() => _QrPayPageState();
}

class _QrPayPageState extends State<QrPayPage> {
  final manualQr = TextEditingController();
  bool busy = false;
  bool scannerActive = true;
  bool torch = false;
  String? lastScanned;
  Json? inspectedInvoice;
  Json? inspectedSession;
  int? inspectedBalance;
  String? error;
  MobileScannerController? controller;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController();
  }

  @override
  void dispose() {
    controller?.dispose();
    manualQr.dispose();
    super.dispose();
  }

  Future<void> inspect(String qr) async {
    final trimmed = qr.trim();
    if (trimmed.isEmpty || busy) return;
    setState(() {
      busy = true;
      error = null;
      lastScanned = trimmed;
    });
    try {
      final r = await widget.service.inspectPaymentQr(trimmed);
      if (!mounted) return;
      setState(() {
        inspectedInvoice = r['invoice'] as Json?;
        inspectedSession = r['session'] as Json?;
        inspectedBalance = (r['balance'] as num?)?.toInt();
        scannerActive = false;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmPay() async {
    final inv = inspectedInvoice;
    if (inv == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.payWithWallet(invoiceId: inv['id'] as String);
      if (!mounted) return;
      showMessage(
        context,
        'Pembayaran Dompet QPark berhasil! QR keluar sudah aktif di Aktivitas.',
      );
      Navigator.pop(context);
      widget.onOpenActivity();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = inspectedInvoice;
    final sess = inspectedSession;
    final balance = inspectedBalance ?? widget.service.walletBalance;
    final amount = (inv?['amount'] as num?)?.toInt() ?? 0;
    final enough = balance >= amount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Bayar Parkir'),
        actions: [
          if (scannerActive)
            IconButton(
              tooltip: 'Lampu kilat',
              icon: Icon(torch ? Icons.flash_on : Icons.flash_off),
              onPressed: () {
                controller?.toggleTorch();
                setState(() => torch = !torch);
              },
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (inv == null) ...[
                    Container(
                      height: 290,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primary, width: 2),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            controller: controller,
                            onDetect: (capture) {
                              if (busy || !scannerActive) return;
                              for (final barcode in capture.barcodes) {
                                final value = barcode.rawValue;
                                if (value != null &&
                                    value.isNotEmpty &&
                                    value != lastScanned) {
                                  inspect(value);
                                  break;
                                }
                              }
                            },
                            errorBuilder: (context, err) => Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  'Kamera tidak tersedia di perangkat/browser ini.\nGunakan input kode QR di bawah.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: Center(
                              child: Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white70,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Arahkan kamera ke QR tagihan parkir dari petugas atau layar pembayaran untuk membayar langsung dengan Dompet QPark.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Input kode QR manual (bantuan web / demo)',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            key: const Key('qr-pay-input'),
                            controller: manualQr,
                            enabled: !busy,
                            decoration: const InputDecoration(
                              labelText: 'Kode QR Tagihan',
                              hintText: 'QPP.SIMULASI.INV-...',
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const Key('qr-pay-check'),
                            onPressed: busy
                                ? null
                                : () => inspect(manualQr.text),
                            icon: busy
                                ? const ActionProgress()
                                : const Icon(Icons.search),
                            label: Text(
                              busy ? 'Memeriksa tagihan…' : 'Periksa Tagihan',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: const BoxDecoration(
                                color: AppColors.successBackground,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.receipt_long_rounded,
                                color: AppColors.primary,
                                size: 36,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Konfirmasi Bayar Parkir',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          _row(
                            'Lokasi',
                            sess?['location_name'] as String? ?? 'QPark',
                          ),
                          _row('No. Plat', sess?['plate'] as String? ?? '—'),
                          _row(
                            'Jenis Kendaraan',
                            sess?['vehicle_type'] == 'MOTOR'
                                ? 'Motor'
                                : 'Mobil',
                          ),
                          _row('Waktu Masuk', wib(sess?['entered_at'])),
                          _row('Total Tagihan', money(amount), bold: true),
                          const Divider(height: 24),
                          _row(
                            'Saldo Dompet QPark',
                            money(balance),
                            valueColor: enough
                                ? AppColors.primary
                                : AppColors.danger,
                            bold: true,
                          ),
                          if (!enough) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Saldo tidak cukup. Kurang ${money(amount - balance)}.',
                              style: const TextStyle(color: AppColors.danger),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onOpenWallet();
                              },
                              icon: const Icon(
                                Icons.account_balance_wallet_outlined,
                              ),
                              label: const Text('Top Up Dompet QPark'),
                            ),
                          ] else ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              key: const Key('qr-pay-confirm'),
                              onPressed: busy ? null : confirmPay,
                              icon: busy
                                  ? const ActionProgress()
                                  : const Icon(Icons.check_circle_outline),
                              label: Text(
                                busy
                                    ? 'Memproses pembayaran…'
                                    : 'Bayar ${money(amount)} pakai Dompet QPark',
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    inspectedInvoice = null;
                                    inspectedSession = null;
                                    lastScanned = null;
                                    scannerActive = true;
                                  }),
                            child: const Text('Scan QR Lain'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    SurfaceCard(
                      child: Text(
                        error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    bool bold = false,
    Color? valueColor,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor ?? AppColors.text,
          ),
        ),
      ],
    ),
  );
}
