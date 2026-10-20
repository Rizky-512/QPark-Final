import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../common.dart';

class EntryPage extends StatefulWidget {
  const EntryPage({super.key, required this.args});
  final ScreenArgs args;
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  final plate = TextEditingController();
  Vehicle vehicle = Vehicle.motor;
  bool busy = false;
  @override
  void dispose() {
    plate.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    widget.args.busy(true);
    try {
      final visit = await widget.args.service.enter(
        widget.args.session,
        plate.text,
        vehicle,
      );
      if (!mounted) return;
      plate.clear();
      vehicle = Vehicle.motor;
      widget.args.dirty(false);
      await showReceipt(context, visit);
    } catch (e) {
      if (mounted) widget.args.error(context, e);
    } finally {
      widget.args.busy(false);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading('Kendaraan masuk', 'Catat kendaraan yang baru tiba.'),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.login_rounded, color: AppColors.primary),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Data kendaraan',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                key: const Key('entry-plate'),
                controller: plate,
                enabled: !busy,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => widget.args.dirty(
                  plate.text.isNotEmpty || vehicle != Vehicle.motor,
                ),
                onSubmitted: (_) => save(),
                decoration: const InputDecoration(
                  labelText: 'Nomor polisi',
                  hintText: 'Contoh: B 1234 ABC',
                  helperText: '3–12 huruf atau angka. Spasi akan dihapus.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<Vehicle>(
                initialValue: vehicle,
                isExpanded: true,
                key: ValueKey(vehicle),
                decoration: const InputDecoration(labelText: 'Jenis kendaraan'),
                items: Vehicle.values
                    .map(
                      (v) => DropdownMenuItem(value: v, child: Text(v.label)),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) {
                        setState(() => vehicle = v!);
                        widget.args.dirty(
                          plate.text.isNotEmpty || vehicle != Vehicle.motor,
                        );
                      },
              ),
              const SizedBox(height: 24),
              const Text(
                'Waktu masuk dicatat otomatis. Tarif saat masuk berlaku sampai kendaraan keluar.',
                style: TextStyle(color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('entry-save'),
                onPressed: busy ? null : save,
                icon: const Icon(Icons.add_circle_outline),
                label: Text(busy ? 'Menyimpan…' : 'Simpan kendaraan masuk'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
