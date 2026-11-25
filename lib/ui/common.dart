import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:intl/intl.dart';
import 'widgets/page_motion.dart';

abstract final class AppColors {
  static const primary = Color(0xFF166534),
      accent = Color(0xFF166534),
      background = Color(0xFFF7F8FA),
      surface = Color(0xFFFFFFFF),
      text = Color(0xFF182230),
      muted = Color(0xFF667085),
      border = Color(0xFFE4E7EC),
      successBackground = Color(0xFFEAF5ED),
      warning = Color(0xFF93370D),
      warningBackground = Color(0xFFFFF4E5),
      danger = Color(0xFFB42318),
      dangerBackground = Color(0xFFFDEDEB);
}

const List<(String, int)> qparkThemeColorOptions = [
  ('Hijau QPark', 0xFF166534),
  ('Emerald', 0xFF059669),
  ('Teal', 0xFF0F766E),
  ('Biru Laut', 0xFF1D4ED8),
  ('Indigo', 0xFF4338CA),
  ('Ungu', 0xFF7E22CE),
  ('Oranye', 0xFFC2410C),
  ('Crimson', 0xFFBE123C),
];

ThemeData buildTheme({
  Color seedColor = AppColors.primary,
  Brightness brightness = Brightness.light,
}) {
  final isDark = brightness == Brightness.dark;
  final surface = isDark ? const Color(0xFF182026) : AppColors.surface;
  final background = isDark ? const Color(0xFF0F1419) : AppColors.background;
  final border = isDark ? const Color(0xFF2B3640) : AppColors.border;
  final onSurface = isDark ? const Color(0xFFF2F4F7) : AppColors.text;
  final indicator = isDark
      ? seedColor.withValues(alpha: 0.25)
      : Color.alphaBlend(seedColor.withValues(alpha: 0.14), Colors.white);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: QParkPageTransitions(),
        TargetPlatform.windows: QParkPageTransitions(),
        TargetPlatform.linux: QParkPageTransitions(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: brightness,
        ).copyWith(
          primary: seedColor,
          secondary: seedColor,
          surface: surface,
          onSurface: onSurface,
          error: AppColors.danger,
        ),
    textTheme: TextTheme(
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -.4,
        color: onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: onSurface),
      bodySmall: const TextStyle(
        fontSize: 12,
        height: 1.4,
        color: AppColors.muted,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: indicator,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: surface,
      foregroundColor: onSurface,
      surfaceTintColor: surface,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: seedColor, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: seedColor,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: DividerThemeData(color: border),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

String money(int? value) =>
    'Rp${NumberFormat.decimalPattern('id_ID').format(value ?? 0)}';
String durationText(Duration d) =>
    '${d.inHours} jam ${d.inMinutes.remainder(60)} menit ${d.inSeconds.remainder(60)} detik';

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: error ? AppColors.danger : AppColors.primary,
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: AppColors.surface,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  String action = 'Lanjutkan',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        scrollable: true,
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      spacing: 20,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
        ?action,
      ],
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = 20});
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.problem = false,
    this.pending = false,
  });
  final String label;
  final bool problem;
  final bool pending;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: problem
          ? AppColors.dangerBackground
          : pending
          ? AppColors.warningBackground
          : AppColors.successBackground,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          problem
              ? Icons.block_rounded
              : pending
              ? Icons.schedule
              : Icons.check_circle_outline_rounded,
          size: 16,
          color: problem
              ? AppColors.danger
              : pending
              ? AppColors.warning
              : AppColors.primary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: problem
                  ? AppColors.danger
                  : pending
                  ? AppColors.warning
                  : AppColors.primary,
            ),
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.title = 'Belum ada kendaraan',
    this.description = 'Kendaraan yang masuk akan tampil di sini.',
  });
  final String title, description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Center(
      child: Column(
        children: [
          const Icon(
            Icons.local_parking_rounded,
            size: 44,
            color: AppColors.accent,
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

/// Compact progress feedback that respects reduced-motion preferences.
class ActionProgress extends StatelessWidget {
  const ActionProgress({super.key});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 18,
    child: MediaQuery.disableAnimationsOf(context)
        ? const Icon(Icons.hourglass_top_rounded, size: 18)
        : const CircularProgressIndicator(
            strokeWidth: 2,
            semanticsLabel: 'Memproses',
          ),
  );
}
