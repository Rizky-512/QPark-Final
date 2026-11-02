import 'package:flutter/material.dart';
import '../common.dart';
import '../remote_common.dart';
import '../widgets/customer_link.dart';
import '../../domain/customer_status.dart';
import '../widgets/parking_cost_card.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key, required this.args, this.active = true});
  final bool active;
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
    final status = CustomerStatus.resolve(
      hasVehicle: service.selected != null,
      online: service.online,
      loading: service.syncing && service.error == null,
      pending: service.pending.isNotEmpty,
      ticket: service.ticket,
      now: service.serverNow,
    );
    Future<void> primaryAction() async {
      switch (status.action) {
        case CustomerAction.addVehicle:
          await edit();
        case CustomerAction.refresh:
          await service.sync();
        case CustomerAction.reconcile:
          try {
            await service.retryPending();
          } catch (error) {
            if (context.mounted) remoteError(context, error);
          }
        case CustomerAction.payment || CustomerAction.exitQr:
          widget.args.navigate(1);
        case CustomerAction.history:
          widget.args.navigate(2);
        case CustomerAction.link:
          break;
      }
    }

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
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                status.title,
                key: const Key('customer-status'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(status.description),
              if (!service.online && service.syncing)
                const LinearProgressIndicator(),
              if (service.ticket != null) ...[
                const SizedBox(height: 16),
                SessionSummary(service.ticket!),
              ],
              if (status.action != CustomerAction.link) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('customer-primary'),
                  onPressed:
                      service.retrying ||
                          (status.action == CustomerAction.refresh &&
                              service.syncing)
                      ? null
                      : primaryAction,
                  icon: Icon(
                    status.action == CustomerAction.exitQr
                        ? Icons.qr_code
                        : Icons.arrow_forward,
                  ),
                  label: Text(status.label),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (status.action == CustomerAction.link) ...[
          CustomerLinkCard(
            key: ValueKey('${service.operationOwner}:${service.selected}'),
            service: service,
          ),
          const SizedBox(height: 24),
        ],
        if (service.ticket != null &&
            service.ticket!['state'] != 'COMPLETED') ...[
          ParkingCostCard(
            session: service.ticket!,
            service: service,
            active: widget.active,
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
