import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../common.dart';

class VehiclePie extends StatelessWidget {
  const VehiclePie({super.key, required this.cars, required this.motors});
  final int cars, motors;
  @override
  Widget build(BuildContext context) {
    final total = cars + motors;
    if (total == 0) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('Belum ada kunjungan pada periode ini.'),
      );
    }
    final carPercent = cars / total * 100;
    Widget legend(String label, int count, double pct, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, color: color, size: 14),
        const SizedBox(width: 10),
        Text(
          '$label  ${pct.toStringAsFixed(1)}%\n$count kunjungan',
          style: const TextStyle(height: 1.6, fontWeight: FontWeight.w600),
        ),
      ],
    );
    return Wrap(
      spacing: 32,
      runSpacing: 20,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          label:
              'Mobil ${carPercent.toStringAsFixed(1)} persen, motor ${(100 - carPercent).toStringAsFixed(1)} persen',
          image: true,
          child: CustomPaint(
            size: const Size(200, 200),
            painter: _Pie(cars / total),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            legend('Motor', motors, 100 - carPercent, const Color(0xFFF0B44C)),
            const SizedBox(height: 18),
            legend('Mobil', cars, carPercent, AppColors.primary),
          ],
        ),
      ],
    );
  }
}

class _Pie extends CustomPainter {
  _Pie(this.carFraction);
  final double carFraction;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()..color = const Color(0xFFF0B44C);
    canvas.drawOval(rect, paint);
    if (carFraction >= 1) {
      canvas.drawOval(rect, paint..color = AppColors.primary);
    } else if (carFraction > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * carFraction,
        true,
        paint..color = AppColors.primary,
      );
    }
  }

  @override
  bool shouldRepaint(_Pie oldDelegate) =>
      oldDelegate.carFraction != carFraction;
}
