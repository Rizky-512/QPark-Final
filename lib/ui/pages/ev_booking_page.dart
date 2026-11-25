import 'package:flutter/material.dart';
import '../../logic/remote_service.dart';
import '../common.dart';
import '../remote_common.dart';
import 'driver_page.dart';

/// EV Charging Station booking screen.
/// Enforces registered Indonesian blue-plate EV vehicles (simulasi).
class EvBookingPage extends StatefulWidget {
  const EvBookingPage({
    super.key,
    required this.service,
    this.initialLocationId,
  });
  final RemoteService service;
  final String? initialLocationId;

  @override
  State<EvBookingPage> createState() => _EvBookingPageState();
}

class _EvBookingPageState extends State<EvBookingPage> {
  String? locationId;
  String? selectedPlate;
  int durationHours = 1;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    locationId =
        widget.initialLocationId ??
        widget.service.selectedLocationId ??
        (widget.service.locations.isNotEmpty
            ? widget.service.locations.first['id'] as String
            : 'LOC-DEFAULT');
    final evs = widget.service.registeredEvPlates;
    if (evs.isNotEmpty) selectedPlate = evs.first;
    widget.service.refreshEvBookings().catchError((_) {});
  }

  Future<void> book() async {
    final loc = locationId;
    final plate = selectedPlate;
    if (loc == null || plate == null || busy) return;
    setState(() => busy = true);
    try {
      await widget.service.bookEv(
        locationId: loc,
        plate: plate,
        durationHours: durationHours,
      );
      if (!mounted) return;
      showMessage(
        context,
        'Booking EV Charging untuk $plate berhasil ($durationHours jam).',
      );
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel(String bookingId) async {
    if (busy) return;
    if (!await confirm(
      context,
      title: 'Batalkan booking EV?',
      body: 'Slot charging EV akan langsung dilepas untuk pengguna lain.',
      action: 'Batalkan booking',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await widget.service.cancelEvBooking(bookingId);
      if (mounted) showMessage(context, 'Booking EV dibatalkan.');
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final service = widget.service;
        final locs = service.locations;
        final evPlates = service.registeredEvPlates;
        if (selectedPlate != null && !evPlates.contains(selectedPlate)) {
          selectedPlate = evPlates.isEmpty ? null : evPlates.first;
        }
        selectedPlate ??= evPlates.isEmpty ? null : evPlates.first;

        final activeLoc =
            locs.where((l) => l['id'] == locationId).firstOrNull ??
            (locs.isNotEmpty ? locs.first : null);
        final evInfo = activeLoc?['ev'] as Map?;
        final evAvail = (evInfo?['available'] as num?)?.toInt() ?? 0;
        final evTotal = (evInfo?['total'] as num?)?.toInt() ?? 0;
        final evRate = (evInfo?['rate'] as num?)?.toInt() ?? 10000;
        final primary = Theme.of(context).colorScheme.primary;

        return Scaffold(
          appBar: AppBar(title: const Text('Book EV Charging')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [primary, const Color(0xFF0284C7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.ev_station_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'EV Charging Station',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Khusus kendaraan listrik ber-plat nomor biru terdaftar · ${money(evRate)}/jam',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Pesan Slot Charging EV',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 14),
                            if (locs.isNotEmpty)
                              DropdownButtonFormField<String>(
                                key: ValueKey('ev-loc-$locationId'),
                                isExpanded: true,
                                initialValue:
                                    locs.any((l) => l['id'] == locationId)
                                    ? locationId
                                    : locs.first['id'] as String,
                                decoration: const InputDecoration(
                                  labelText: 'Lokasi Charging Station',
                                ),
                                items: locs.map((l) {
                                  final ev = l['ev'] as Map?;
                                  final avail =
                                      (ev?['available'] as num?)?.toInt() ?? 0;
                                  final tot =
                                      (ev?['total'] as num?)?.toInt() ?? 0;
                                  return DropdownMenuItem(
                                    value: l['id'] as String,
                                    child: Text(
                                      '${l['name']} ($avail/$tot slot EV)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: busy
                                    ? null
                                    : (v) => setState(() => locationId = v),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  Icons.bolt_rounded,
                                  color: evAvail > 0
                                      ? primary
                                      : AppColors.danger,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    evTotal == 0
                                        ? 'Lokasi ini belum memiliki slot EV Charging.'
                                        : '$evAvail dari $evTotal slot EV tersedia (${money(evRate)}/jam)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: evAvail > 0
                                          ? primary
                                          : AppColors.danger,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (evPlates.isEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFF93C5FD),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.verified_outlined,
                                          color: Color(0xFF1D4ED8),
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Belum ada kendaraan plat biru',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF1E3A8A),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Booking EV Charging wajib memakai kendaraan ber-plat nomor biru (EV) yang sudah terdaftar (simulasi).',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF1E40AF),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    FilledButton.icon(
                                      key: const Key('ev-register-blue-plate'),
                                      onPressed: () => showVehicleEditorDialog(
                                        context,
                                        service,
                                        defaultEv: true,
                                      ),
                                      icon: const Icon(Icons.add),
                                      label: const Text(
                                        'Daftarkan Kendaraan Plat Biru',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              DropdownButtonFormField<String>(
                                key: ValueKey('ev-plate-$selectedPlate'),
                                isExpanded: true,
                                initialValue: selectedPlate,
                                decoration: const InputDecoration(
                                  labelText: 'Kendaraan Plat Biru (EV)',
                                ),
                                items: evPlates
                                    .map(
                                      (p) => DropdownMenuItem(
                                        value: p,
                                        child: Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1D4ED8),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'EV',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '$p · ${service.vehicleTypes[p] == 'MOTOR' ? 'Motor' : 'Mobil'}',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: busy
                                    ? null
                                    : (v) => setState(() => selectedPlate = v),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Durasi Charging',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [1, 2, 3, 4]
                                    .map(
                                      (h) => ChoiceChip(
                                        label: Text('$h jam'),
                                        selected: durationHours == h,
                                        onSelected: busy
                                            ? null
                                            : (_) => setState(
                                                () => durationHours = h,
                                              ),
                                      ),
                                    )
                                    .toList(),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Estimasi biaya charging: ${money(evRate * durationHours)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                key: const Key('ev-book-submit'),
                                onPressed:
                                    busy || !service.online || evAvail <= 0
                                    ? null
                                    : book,
                                icon: busy
                                    ? const ActionProgress()
                                    : const Icon(Icons.ev_station_rounded),
                                label: Text(
                                  busy
                                      ? 'Memproses booking…'
                                      : 'Konfirmasi Book EV ($durationHours jam)',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Booking EV Saya',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 10),
                            if (service.evBookings.isEmpty)
                              const EmptyState(
                                title: 'Belum ada booking EV',
                                description:
                                    'Pemesanan slot EV Charging Anda akan muncul di sini.',
                              ),
                            ...service.evBookings.map((b) {
                              final isActive = b['status'] == 'ACTIVE';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor: isActive
                                        ? const Color(0xFFDBEAFE)
                                        : AppColors.border,
                                    child: Icon(
                                      Icons.ev_station_rounded,
                                      color: isActive
                                          ? const Color(0xFF1D4ED8)
                                          : AppColors.muted,
                                    ),
                                  ),
                                  title: Text(
                                    '${b['plate']} · ${b['location_name'] ?? 'QPark'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${b['duration_hours']} jam · ${money((b['estimated_cost'] as num?)?.toInt())} · Sampai ${wib(b['expires_at'])}\nStatus: ${isActive
                                        ? 'Aktif'
                                        : b['status'] == 'CANCELLED'
                                        ? 'Dibatalkan'
                                        : 'Selesai'}',
                                  ),
                                  trailing: isActive
                                      ? TextButton(
                                          onPressed: busy
                                              ? null
                                              : () => cancel(b['id'] as String),
                                          child: const Text(
                                            'Batal',
                                            style: TextStyle(
                                              color: AppColors.danger,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
