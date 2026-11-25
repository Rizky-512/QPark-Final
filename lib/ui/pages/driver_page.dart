import 'package:flutter/material.dart';
import '../../domain/customer_status.dart';
import '../../logic/remote_service.dart';
import '../common.dart';
import '../remote_common.dart';
import '../widgets/customer_ticket_details.dart';
import '../widgets/vehicle_gallery.dart';

Future<void> showVehicleEditorDialog(
  BuildContext context,
  RemoteService service, {
  String? old,
}) async {
  final controller = TextEditingController(text: old);
  String? error;
  String? vehicleType = service.vehicleTypes[old];
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
                helperText: service.customerIdentity == null
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
                      await service.savePlate(
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
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
}

class DriverPage extends StatefulWidget {
  const DriverPage({super.key, required this.args, this.active = true});
  final bool active;
  final RemoteArgs args;
  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  bool detailsOpen = false;
  final _locationsKey = GlobalKey();

  Future<void> openDetails() async {
    if (detailsOpen || widget.args.service.selected == null) return;
    detailsOpen = true;
    try {
      await showCustomerTicketDetails(context, widget.args);
    } finally {
      detailsOpen = false;
    }
  }

  Future<void> edit([String? old]) =>
      showVehicleEditorDialog(context, widget.args.service, old: old);

  Widget _heroHeader(BuildContext context, RemoteService service) {
    final greeting = service.customerIdentity?.displayName ?? 'Pengguna QPark';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 56),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, Color(0xFF15803D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(20),
              bottom: Radius.circular(28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.local_parking_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'QPARK',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          service.ticket != null &&
                                  service.ticket!['state'] != 'COMPLETED'
                              ? Icons.confirmation_number_rounded
                              : Icons.location_on_outlined,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          service.ticket != null &&
                                  service.ticket!['state'] != 'COMPLETED'
                              ? 'Tiket Aktif'
                              : '${service.locations.length <= 1 ? 1 : service.locations.length} Lokasi',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Halo, $greeting',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Parkir lebih mudah',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: -26,
          child: Material(
            color: AppColors.surface,
            elevation: 3,
            shadowColor: Colors.black12,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              key: const Key('home-wallet-card'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => widget.args.navigate(2),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.successBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dompet QPark',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'E-Wallet Prototipe',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      money(service.walletBalance),
                      key: const Key('home-wallet-balance'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickActions(BuildContext context) {
    final actions = [
      (
        'Lokasi',
        Icons.location_on_outlined,
        () {
          final ctx = _locationsKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 300),
            );
          }
        },
      ),
      (
        'Tiket',
        Icons.confirmation_number_outlined,
        () => widget.args.navigate(1),
      ),
      ('Kendaraan', Icons.directions_car_outlined, () => edit()),
      ('Top Up', Icons.add_card_outlined, () => widget.args.navigate(2)),
      (
        'Scan Bayar',
        Icons.qr_code_scanner_rounded,
        () => widget.args.openQrPay?.call(),
      ),
    ];
    return SurfaceCard(
      padding: 14,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: actions
            .map(
              (a) => Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: a.$3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.successBackground,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(a.$2, color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          a.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _locationsSection(BuildContext context, RemoteService service) {
    final locs = service.locations;
    if (locs.isEmpty) return CapacityCard(service);
    final selectedId =
        service.selectedLocationId ??
        (service.capacity?['location'] as Map?)?['id'] as String? ??
        locs.first['id'] as String?;

    return Column(
      key: _locationsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Lokasi Parkir QPark',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${locs.length} area',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 162,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: locs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, idx) {
              final loc = locs[idx];
              final isSelected = loc['id'] == selectedId;
              final cats = loc['categories'] as Map?;
              final carAvail =
                  (cats?['MOBIL']?['available'] as num?)?.toInt() ?? 0;
              final motorAvail =
                  (cats?['MOTOR']?['available'] as num?)?.toInt() ?? 0;
              final carRate = (loc['rates']?['MOBIL'] as num?)?.toInt() ?? 7000;
              return SizedBox(
                width: 272,
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    key: Key('location-card-${loc['id']}'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => service.selectLocation(loc['id'] as String),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.successBackground,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  isSelected ? 'DIPILIH' : 'TERSEDIA',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${money(carRate)}/jam',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            loc['name'] as String? ?? 'Lokasi QPark',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          if ((loc['address'] as String? ?? '').isNotEmpty)
                            Text(
                              loc['address'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          const Spacer(),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.directions_car,
                                    size: 15,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$carAvail Mobil',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.two_wheeler,
                                    size: 15,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$motorAvail Motor',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        CapacityCard(service),
      ],
    );
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
          widget.args.navigate(1);
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
            _locationsSection(context, service),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heroHeader(context, service),
            const SizedBox(height: 40),
            _quickActions(context),
            const SizedBox(height: 18),
            if (service.plates.isNotEmpty) ...[
              VehicleGallery(service: service, onDetails: openDetails),
              const SizedBox(height: 18),
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
            const SizedBox(height: 20),
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
