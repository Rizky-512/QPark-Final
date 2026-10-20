import 'package:flutter/material.dart';
import '../common.dart';
import '../remote_common.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key, required this.args});
  final RemoteArgs args;
  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  Future<void> edit([String? old]) async {
    final controller = TextEditingController(text: old);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(old == null ? 'Tambah kendaraan' : 'Edit nopol'),
          content: TextField(
            key: const Key('vehicle-plate'),
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Nomor polisi',
              hintText: 'B 1234 AB',
              errorText: error,
              errorMaxLines: 3,
              helperText: 'Tersimpan di perangkat ini.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.args.service.savePlate(
                    controller.text,
                    replacing: old,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  if (dialogContext.mounted) {
                    setDialog(() => error = e.toString());
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    // Disposed after the dialog's closing animation no longer uses the field.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.args.service;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading(
          'Parkir lebih mudah',
          'Simpan nopol. Tiket muncul setelah petugas memverifikasi kendaraan masuk.',
        ),
        CapacityCard(service),
        const SizedBox(height: 24),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(
                'Kendaraan saya',
                'Daftar ini tersimpan pada perangkat Anda.',
                action: OutlinedButton.icon(
                  key: const Key('vehicle-add'),
                  onPressed: () => edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah'),
                ),
              ),
              if (service.plates.isEmpty)
                const EmptyState(
                  title: 'Tambahkan nopol kendaraan',
                  description:
                      'Tidak perlu membuat akun. Nopol yang sama boleh disimpan keluarga untuk membantu pembayaran.',
                ),
              ...service.plates.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: service.selected == p
                        ? AppColors.successBackground
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      onTap: () => service.selectPlate(p),
                      leading: Icon(
                        service.selected == p
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        p,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            await edit(p);
                            return;
                          }
                          if (await confirm(
                            context,
                            title: 'Hapus nopol tersimpan?',
                            body:
                                'Sesi parkir dan tagihan tetap ada. Hanya pilihan pada perangkat ini yang dihapus.',
                            action: 'Hapus',
                          )) {
                            try {
                              await service.removePlate(p);
                            } catch (e) {
                              if (context.mounted) remoteError(context, e);
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Hapus')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (service.selected != null)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tiket aktif · ${service.selected}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (service.ticket == null)
                  const EmptyState(
                    title: 'Belum tercatat masuk',
                    description:
                        'Tiket tersedia setelah petugas memverifikasi kendaraan. Anda tidak perlu membuka HP di pintu masuk.',
                  )
                else ...[
                  SessionSummary(service.ticket!),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => widget.args.navigate(1),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(
                      service.ticket!['state'] == 'COMPLETED'
                          ? 'Lihat sesi selesai'
                          : 'Buka tiket & pembayaran',
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
