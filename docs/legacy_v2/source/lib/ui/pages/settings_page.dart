import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.args});
  final ScreenArgs args;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<List<ParkingSetting>> future;
  final dirtyTypes = <Vehicle>{};
  @override
  void initState() {
    super.initState();
    future = widget.args.service.settings(widget.args.session);
  }

  void reload() {
    final next = widget.args.service.settings(widget.args.session);
    setState(() {
      future = next;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PageHeading(
        'Pengaturan parkir',
        'Atur kapasitas dan tarif setiap jenis kendaraan.',
      ),
      LoadPanel(
        future: future,
        retry: reload,
        onExpired: widget.args.expire,
        builder: (settings) => LayoutBuilder(
          builder: (context, bounds) => Wrap(
            spacing: 20,
            runSpacing: 20,
            children: settings
                .map(
                  (setting) => SizedBox(
                    width: bounds.maxWidth >= 800
                        ? (bounds.maxWidth - 20) / 2
                        : bounds.maxWidth,
                    child: _SettingForm(
                      key: ValueKey(setting.vehicle),
                      setting: setting,
                      args: widget.args,
                      onDirty: (dirty) {
                        if (dirty) {
                          dirtyTypes.add(setting.vehicle);
                        } else {
                          dirtyTypes.remove(setting.vehicle);
                        }
                        widget.args.dirty(dirtyTypes.isNotEmpty);
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Perubahan tarif hanya berlaku untuk kendaraan yang masuk setelah disimpan. Kapasitas tidak dapat lebih kecil dari jumlah kendaraan aktif.',
        style: TextStyle(color: AppColors.muted, height: 1.6),
      ),
    ],
  );
}

class _SettingForm extends StatefulWidget {
  const _SettingForm({
    super.key,
    required this.setting,
    required this.args,
    required this.onDirty,
  });
  final ParkingSetting setting;
  final ScreenArgs args;
  final ValueChanged<bool> onDirty;
  @override
  State<_SettingForm> createState() => _SettingFormState();
}

class _SettingFormState extends State<_SettingForm> {
  late final TextEditingController capacity, rate;
  late String savedCapacity, savedRate;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    savedCapacity = '${widget.setting.capacity}';
    savedRate = '${widget.setting.hourlyRate}';
    capacity = TextEditingController(text: savedCapacity);
    rate = TextEditingController(text: savedRate);
  }

  @override
  void dispose() {
    capacity.dispose();
    rate.dispose();
    super.dispose();
  }

  void changed(String _) =>
      widget.onDirty(capacity.text != savedCapacity || rate.text != savedRate);
  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    widget.args.busy(true);
    try {
      await widget.args.service.updateSetting(
        widget.args.session,
        widget.setting.vehicle,
        capacity.text,
        rate.text,
      );
      if (!mounted) return;
      savedCapacity = capacity.text;
      savedRate = rate.text;
      widget.onDirty(false);
      showMessage(
        context,
        'Pengaturan ${widget.setting.vehicle.label.toLowerCase()} berhasil disimpan.',
      );
    } catch (e) {
      if (mounted) widget.args.error(context, e);
    } finally {
      widget.args.busy(false);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              vehicleIcon(widget.setting.vehicle),
              size: 32,
              color: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.setting.vehicle.label,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          controller: capacity,
          enabled: !busy,
          onChanged: changed,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Kapasitas parkir',
            suffixText: 'slot',
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: rate,
          enabled: !busy,
          onChanged: changed,
          onSubmitted: (_) => save(),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Tarif per jam',
            prefixText: 'Rp ',
            suffixText: '/jam',
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: busy ? null : save,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            busy
                ? 'Menyimpan…'
                : 'Simpan ${widget.setting.vehicle.label.toLowerCase()}',
          ),
        ),
      ],
    ),
  );
}
