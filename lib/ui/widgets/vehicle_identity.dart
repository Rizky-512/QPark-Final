import 'package:flutter/material.dart';
import '../common.dart';

/// Local vector artwork keeps the card sharp on desktop without image downloads.
class VehicleIdentity extends StatelessWidget {
  const VehicleIdentity({super.key, required this.plate, this.vehicleType});
  final String plate;
  final String? vehicleType;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 112,
          width: double.infinity,
          child: ExcludeSemantics(
            child: CustomPaint(painter: _VehiclePainter(vehicleType)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          plate,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          vehicleType == 'MOTOR'
              ? 'Motor'
              : vehicleType == 'MOBIL'
              ? 'Mobil'
              : 'Kendaraan tersimpan',
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _VehiclePainter extends CustomPainter {
  _VehiclePainter(this.type);
  final String? type;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / 300).clamp(.1, 1.0);
    canvas.translate((size.width - 300 * scale) / 2, 0);
    canvas.scale(scale, size.height / 112);
    final paint = Paint()..color = const Color(0xFFD8EEDC);
    canvas.drawOval(const Rect.fromLTWH(38, 5, 225, 103), paint);
    paint.color = const Color(0x1F166534);
    canvas.drawOval(const Rect.fromLTWH(30, 91, 244, 14), paint);
    if (type == null) {
      paint.color = AppColors.primary;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(112, 13, 76, 76),
          const Radius.circular(18),
        ),
        paint,
      );
      final text = TextPainter(
        text: const TextSpan(
          text: 'P',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w800,
            fontSize: 54,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(150 - text.width / 2, 14));
      return;
    }
    if (type == 'MOTOR') {
      paint.color = AppColors.text;
      for (final x in [75.0, 229.0]) {
        canvas.drawCircle(Offset(x, 80), 23, paint);
      }
      paint
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round;
      final frame = Path()
        ..moveTo(75, 80)
        ..lineTo(121, 48)
        ..lineTo(161, 79)
        ..lineTo(75, 80)
        ..moveTo(161, 79)
        ..lineTo(201, 42)
        ..lineTo(229, 80)
        ..moveTo(201, 42)
        ..lineTo(191, 22)
        ..lineTo(174, 22);
      canvas.drawPath(frame, paint);
      paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF213C2A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(106, 35, 58, 13),
          const Radius.circular(6),
        ),
        paint,
      );
    } else {
      paint.color = AppColors.primary;
      final roof = Path()
        ..moveTo(73, 57)
        ..lineTo(103, 23)
        ..quadraticBezierTo(110, 17, 124, 17)
        ..lineTo(183, 17)
        ..lineTo(221, 57)
        ..close();
      canvas.drawPath(roof, paint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(37, 51, 228, 40),
          const Radius.circular(15),
        ),
        paint,
      );
      paint.color = const Color(0xFFC3E3D0);
      canvas.drawPath(
        Path()
          ..moveTo(94, 49)
          ..lineTo(116, 26)
          ..lineTo(146, 26)
          ..lineTo(146, 49)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(155, 26)
          ..lineTo(179, 26)
          ..lineTo(204, 49)
          ..lineTo(155, 49)
          ..close(),
        paint,
      );
      paint.color = const Color(0xFFF8E7AC);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(246, 58, 14, 8),
          const Radius.circular(3),
        ),
        paint,
      );
      paint.color = AppColors.text;
      for (final x in [87.0, 217.0]) {
        canvas.drawCircle(Offset(x, 87), 18, paint);
      }
    }
    paint.color = const Color(0xFFB8C9BF);
    for (final x in type == 'MOTOR' ? [75.0, 229.0] : [87.0, 217.0]) {
      canvas.drawCircle(Offset(x, type == 'MOTOR' ? 80 : 87), 8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VehiclePainter oldDelegate) =>
      oldDelegate.type != type;
}
