import 'package:flutter/material.dart';
import '../common.dart';
import '../remote_common.dart';
import '../widgets/customer_link.dart';

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
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          scrollable: true,
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
              helperMaxLines: 3,
              helperText: widget.args.service.customerIdentity == null
                  ? 'Tersimpan di perangkat ini.'
                  : 'Tersimpan pada akun Anda.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialog(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await widget.args.service.savePlate(
                          controller.text,
                          replacing: old,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        if (dialogContext.mounted) {
                          setDialog(() {
                            error = e.toString();
                            saving = false;
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Menyimpan…' : 'Simpan'),
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
          'Simpan nopol, lalu hubungkan tiket melalui kode untuk petugas.',
        ),
        if (service.plates.length > 1) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('selected-${service.selected}'),
            initialValue: service.selected,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Kendaraan yang digunakan',
            ),
            items: service.plates
                .map(
                  (plate) => DropdownMenuItem(value: plate, child: Text(plate)),
                )
                .toList(),
            onChanged: service.selectPlate,
          ),
          const SizedBox(height: 16),
        ],
        if (service.selected != null)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Parkir Anda · ${service.selected}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (service.ticket == null)
                  EmptyState(
                    title: !service.online
                        ? 'Memeriksa tiket'
                        : 'Belum tercatat masuk',
                    description: !service.online
                        ? 'Tiket belum dapat diperbarui. Periksa koneksi lalu coba lagi.'
                        : 'Tiket akan terlihat setelah petugas mencocokkan kendaraan dan menghubungkan kode Anda.',
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
                          : service.ticket!['window_status'] == 'VALID'
                          ? 'Tampilkan QR keluar'
                          : 'Buka tiket & pembayaran',
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 24),
        if (service.selected != null && service.ticket == null) ...[
          CustomerLinkCard(
            key: ValueKey('${service.operationOwner}:${service.selected}'),
            service: service,
          ),
          const SizedBox(height: 24),
        ],
        CapacityCard(service),
        const SizedBox(height: 24),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(
                'Kendaraan saya',
                service.customerIdentity == null
                    ? 'Pilih kendaraan yang sedang Anda gunakan.'
                    : 'Kendaraan tersimpan pada akun Anda.',
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
                      'Ketuk Tambah, lalu isi nopol. Tiket muncul setelah petugas mencatat kendaraan masuk.',
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
      ],
    );
  }
}
