import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key, required this.title, required this.accepts});
  final String title;
  final bool Function(String) accepts;
  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  bool accepted = false;
  String? notice;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Column(
      children: [
        if (notice != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(notice!)),
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              if (accepted) return;
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && widget.accepts(value)) {
                  accepted = true;
                  Navigator.pop(context, value);
                  return;
                }
              }
              if (notice == null) {
                setState(
                  () => notice =
                      'QR tidak sesuai atau sudah kedaluwarsa. Pindai QR yang diminta pada layar ini.',
                );
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
                      'Kamera tidak tersedia. Izinkan kamera dan gunakan HTTPS atau localhost. Anda tetap dapat memasukkan kode secara manual.',
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Kembali ke input manual'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
