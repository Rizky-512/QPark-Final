import 'package:flutter/material.dart';
import '../common.dart';

/// Only inserted for a SUCCESS response matching the current ticket/account.
/// The QR is deliberately outside this animation.
class PaymentConfirmation extends StatelessWidget {
  const PaymentConfirmation({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: TweenAnimationBuilder<double>(
      tween: Tween(
        begin: MediaQuery.disableAnimationsOf(context) ? 1 : .7,
        end: 1,
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.successBackground,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 38,
              color: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pembayaran terkonfirmasi',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text(
                    'Simulasi berhasil. QR keluar siap ditunjukkan kepada petugas.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
