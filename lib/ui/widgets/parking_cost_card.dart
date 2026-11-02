import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/remote_repository.dart';
import '../../domain/parking_cost.dart';
import '../../logic/remote_service.dart';
import '../common.dart';
import '../remote_common.dart';

class ParkingCostCard extends StatefulWidget {
  const ParkingCostCard({
    super.key,
    required this.session,
    required this.service,
    this.active = true,
  });
  final Json session;
  final RemoteService service;
  final bool active;
  @override
  State<ParkingCostCard> createState() => _ParkingCostCardState();
}

class _ParkingCostCardState extends State<ParkingCostCard> {
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          widget.active &&
          widget.service.foreground &&
          widget.session['state'] != 'COMPLETED') {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cost = ParkingCost.fromSession(
      widget.session,
      widget.service.serverNow,
    );
    final deadline = (widget.session['window'] as Map?)?['deadline'];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            cost.serverInvoice
                ? 'Tagihan aktif dari server'
                : cost.additional
                ? 'Perkiraan tambahan'
                : 'Perkiraan biaya saat ini',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            money(cost.amount),
            key: const Key('parking-cost'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('Tarif sesi: ${money(cost.rate)}/jam'),
          Text('Durasi: ${durationText(Duration(seconds: cost.seconds))}'),
          if (!cost.serverInvoice &&
              !cost.additional &&
              (widget.session['amount_paid'] as num? ?? 0) == 0)
            Text('${cost.hours} jam dihitung x ${money(cost.rate)}'),
          Text(
            'Sudah dibayar: ${money((widget.session['amount_paid'] as num? ?? 0).toInt())}',
          ),
          const SizedBox(height: 8),
          const Text(
            'Minimum 1 jam; jam penuh dibulatkan ke bawah. Contoh: 1 jam 40 menit dihitung 1 jam, tepat 2 jam dihitung 2 jam.',
          ),
          if (!cost.serverInvoice)
            const Text(
              'Ini perkiraan, bukan tagihan final. Nilai yang dibayar mengikuti tagihan server.',
            ),
          if (!widget.service.online)
            const Text(
              'Data terakhir: sambungkan kembali untuk memastikan status dan biaya terbaru.',
            ),
          if (deadline is num && widget.session['state'] != 'COMPLETED') ...[
            const SizedBox(height: 12),
            Text('Batas keluar: ${wib(deadline)}'),
            Text(
              'Sisa waktu keluar: ${remaining(deadline, widget.service.serverNow)}',
            ),
          ],
          const Text(
            'Setelah pembayaran, tersedia 15 menit untuk keluar. Jika terlewati, tambahan 1 jam mengikuti tarif sesi; tambahan tertunda tidak menumpuk.',
          ),
        ],
      ),
    );
  }
}
