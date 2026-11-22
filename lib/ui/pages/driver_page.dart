import 'package:flutter/material.dart';
import '../common.dart';
import '../remote_common.dart';
import '../widgets/customer_ticket_details.dart';
import '../widgets/vehicle_gallery.dart';
import '../../domain/customer_status.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key, required this.args, this.active = true});
  final bool active;
  final RemoteArgs args;
  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  bool detailsOpen = false;
  Future<void> openDetails() async {
    if (detailsOpen || widget.args.service.selected == null) return;
    detailsOpen = true;
    try {
      await showCustomerTicketDetails(context, widget.args);
    } finally {
      detailsOpen = false;
    }
  }

  Future<void> edit([String? old]) async {
    final controller = TextEditingController(text: old);
    String? error;
    String? vehicleType = widget.args.service.vehicleTypes[old];
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          scrollable: true,
          title: Text(old == null ? 'Tambah kendaraan' : 'Edit nopol'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
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
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('vehicle-category'),
                initialValue: vehicleType,
                decoration: const InputDecoration(
                  labelText: 'Kategori kendaraan',
                ),
                items: const [
                  DropdownMenuItem(value: 'MOBIL', child: Text('Mobil')),
                  DropdownMenuItem(value: 'MOTOR', child: Text('Motor')),
                ],
                onChanged: saving
                    ? null
                    : (v) => setDialog(() => vehicleType = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: saving || vehicleType == null
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
                          vehicleType: vehicleType,
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
          await openDetails();
      }
    }

    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 960;
        final overview = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.local_parking_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status.title,
                          key: const Key('customer-status'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    status.description,
                    style: const TextStyle(color: AppColors.muted),
                  ),
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
                  if (service.ticket != null)
                    TextButton.icon(
                      onPressed: openDetails,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Rincian tiket & biaya'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            CapacityCard(service),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeading(
              'Parkir lebih mudah',
              'Kendaraan Anda, tiket Anda. Semua dalam satu tempat.',
              action: OutlinedButton.icon(
                key: const Key('vehicle-add'),
                onPressed: () => edit(),
                icon: const Icon(Icons.add),
                label: const Text('Tambah kendaraan'),
              ),
            ),
            if (service.plates.isNotEmpty) ...[
              VehicleGallery(service: service, onDetails: openDetails),
              const SizedBox(height: 20),
            ],
            if (wide && service.selected != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: overview),
                  const SizedBox(width: 24),
                  Expanded(
                    child: SurfaceCard(
                      key: const Key('desktop-ticket-panel'),
                      child: CustomerTicketDetails(
                        args: widget.args,
                        active: widget.active,
                      ),
                    ),
                  ),
                ],
              )
            else
              overview,
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
                      key: const Key('vehicle-manage-add'),
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
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Hapus'),
                              ),
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
      },
    );
  }
}
