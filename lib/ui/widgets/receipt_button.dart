import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/remote_repository.dart';
import '../../domain/parking_receipt.dart';
import '../common.dart';

class ReceiptButton extends StatelessWidget {
  const ReceiptButton({super.key, required this.session});
  final Json session;
  @override
  Widget build(BuildContext context) {
    if (!ParkingReceipt.available(session)) return const SizedBox.shrink();
    return OutlinedButton.icon(
      icon: const Icon(Icons.receipt_long_outlined),
      label: const Text('Lihat bukti transaksi'),
      onPressed: () {
        final receipt = ParkingReceipt.fromSession(session);
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: const Text('Bukti transaksi'),
            content: SelectableText(receipt.text),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: receipt.text));
                  if (context.mounted) {
                    showMessage(context, 'Bukti transaksi disalin.');
                  }
                },
                child: const Text('Salin teks'),
              ),
              Builder(
                builder: (context) => FilledButton.icon(
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Bagikan'),
                  onPressed: () async {
                    try {
                      final box = context.findRenderObject() as RenderBox?;
                      final result = await SharePlus.instance.share(
                        ShareParams(
                          text: receipt.text,
                          subject: 'Bukti transaksi QPark ${session['id']}',
                          sharePositionOrigin: box == null
                              ? null
                              : box.localToGlobal(Offset.zero) & box.size,
                          mailToFallbackEnabled: false,
                        ),
                      );
                      if (result.status == ShareResultStatus.unavailable &&
                          context.mounted) {
                        showMessage(
                          context,
                          'Status berbagi tidak tersedia. Jika bukti belum terbagi, gunakan Salin teks.',
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        showMessage(
                          context,
                          'Berbagi belum tersedia di perangkat ini. Gunakan Salin teks.',
                          error: true,
                        );
                      }
                    }
                  },
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
            ],
          ),
        );
      },
    );
  }
}
