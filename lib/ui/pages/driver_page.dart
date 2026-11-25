import 'dart:async';
import 'dart:convert';
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
  bool defaultEv = false,
}) async {
  final controller = TextEditingController(text: old);
  String? error;
  String? vehicleType =
      service.vehicleTypes[old] ?? (defaultEv ? 'MOBIL' : null);
  bool isEv = old != null ? (service.evPlates[old] == true) : defaultEv;
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
            const SizedBox(height: 12),
            CheckboxListTile(
              key: const Key('vehicle-is-ev'),
              contentPadding: EdgeInsets.zero,
              value: isEv,
              onChanged: saving ? null : (v) => setDialog(() => isEv = v!),
              title: const Text(
                'Kendaraan listrik (Plat nomor biru)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Wajib dicentang (simulasi plat biru terdaftar) untuk Book EV Charging.',
                style: TextStyle(fontSize: 12),
              ),
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
                        isEv: isEv,
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
  const DriverPage({
    super.key,
    required this.args,
    this.active = true,
    this.fullBleed = false,
    this.onStaffLogin,
  });
  final bool active;
  final bool fullBleed;
  final RemoteArgs args;
  final VoidCallback? onStaffLogin;
  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  bool detailsOpen = false;
  final PageController _slideController = PageController(
    viewportFraction: 0.94,
  );
  Timer? _autoSlideTimer;
  int _slideIndex = 0;

  @override
  void initState() {
    super.initState();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      final locs = widget.args.service.locations;
      if (!mounted ||
          !widget.active ||
          !widget.args.service.foreground ||
          locs.length < 2 ||
          !_slideController.hasClients) {
        return;
      }
      final next = (_slideIndex + 1) % locs.length;
      _slideController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _slideController.dispose();
    super.dispose();
  }

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

  Widget _miniAvatar(RemoteService service) {
    final b64 = service.activeCustomAvatarBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 16,
          backgroundImage: MemoryImage(base64Decode(b64)),
        );
      } catch (_) {}
    }
    final url = service.customerIdentity?.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(radius: 16, backgroundImage: NetworkImage(url));
    }
    return const SizedBox.shrink();
  }

  Widget _heroHeader(BuildContext context, RemoteService service) {
    final primary = Theme.of(context).colorScheme.primary;
    final darkShade = Color.lerp(primary, Colors.black, 0.22)!;
    final greeting = service.customerIdentity?.displayName ?? 'Pengguna QPark';
    final topPad = widget.fullBleed
        ? MediaQuery.paddingOf(context).top + 14
        : 20.0;
    final hasAvatar =
        (service.activeCustomAvatarBase64?.isNotEmpty ?? false) ||
        (service.customerIdentity?.avatarUrl?.isNotEmpty ?? false);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20, topPad, 14, 58),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [darkShade, primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: widget.fullBleed
                ? const BorderRadius.vertical(bottom: Radius.circular(28))
                : const BorderRadius.vertical(
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
                    Icons.location_on_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'QPARK',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  if (hasAvatar) ...[
                    GestureDetector(
                      onTap: () => widget.args.navigate(3),
                      child: _miniAvatar(service),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (widget.fullBleed && widget.onStaffLogin != null)
                    IconButton(
                      key: const Key('officer-login'),
                      tooltip: 'Login pengelola / petugas',
                      onPressed: widget.onStaffLogin,
                      icon: const Icon(
                        Icons.badge_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Halo, $greeting',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Parkir lebih mudah',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          service.ticket != null &&
                                  service.ticket!['state'] != 'COMPLETED'
                              ? Icons.confirmation_number_rounded
                              : Icons.ev_station_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          service.ticket != null &&
                                  service.ticket!['state'] != 'COMPLETED'
                              ? 'Tiket Aktif'
                              : '${service.evBookings.where((b) => b['status'] == 'ACTIVE').length} EV Aktif',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: -26,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
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
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: primary,
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
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: primary),
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
    final primary = Theme.of(context).colorScheme.primary;
    final actions = [
      (
        const Key('quick-book-ev'),
        'Book EV',
        Icons.ev_station_rounded,
        const Color(0xFF0284C7),
        () => widget.args.openEvBook?.call(),
      ),
      (
        const Key('quick-vehicle'),
        'Kendaraan',
        Icons.directions_car_outlined,
        primary,
        () => edit(),
      ),
      (
        const Key('quick-topup'),
        'Top Up',
        Icons.add_card_rounded,
        primary,
        () => widget.args.navigate(2),
      ),
      (
        const Key('quick-qr'),
        'QR',
        Icons.qr_code_scanner_rounded,
        primary,
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
                  key: a.$1,
                  borderRadius: BorderRadius.circular(14),
                  onTap: a.$5,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: a.$4.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(a.$3, color: a.$4, size: 24),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          a.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
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

  /// Replaces Parkee's "Promosi" auto-slider with live Parking + EV Charging availability per location.
  Widget _availabilityAutoSlider(BuildContext context, RemoteService service) {
    final locs = service.locations;
    if (locs.isEmpty) return CapacityCard(service);
    final primary = Theme.of(context).colorScheme.primary;
    final clampedIndex = _slideIndex.clamp(0, locs.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Ketersediaan Parkir & EV',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                locs.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.only(left: 4),
                  width: clampedIndex == i ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: clampedIndex == i
                        ? primary
                        : primary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 214,
          child: PageView.builder(
            key: const Key('availability-slider'),
            controller: _slideController,
            itemCount: locs.length,
            onPageChanged: (i) {
              setState(() => _slideIndex = i);
              service.selectLocation(locs[i]['id'] as String);
            },
            itemBuilder: (context, idx) {
              final loc = locs[idx];
              final cats = loc['categories'] as Map?;
              final carAvail =
                  (cats?['MOBIL']?['available'] as num?)?.toInt() ?? 0;
              final carTotal = (cats?['MOBIL']?['total'] as num?)?.toInt() ?? 0;
              final motorAvail =
                  (cats?['MOTOR']?['available'] as num?)?.toInt() ?? 0;
              final motorTotal =
                  (cats?['MOTOR']?['total'] as num?)?.toInt() ?? 0;
              final ev = loc['ev'] as Map?;
              final evAvail = (ev?['available'] as num?)?.toInt() ?? 0;
              final evTotal = (ev?['total'] as num?)?.toInt() ?? 0;

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('location-card-${loc['id']}'),
                    onTap: () => service.selectLocation(loc['id'] as String),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            color: primary,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    loc['name'] as String? ?? 'Lokasi QPark',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                10,
                                14,
                                10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if ((loc['address'] as String? ?? '')
                                      .isNotEmpty)
                                    Text(
                                      loc['address'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _slotChip(
                                        Icons.directions_car,
                                        'Mobil',
                                        '$carAvail/$carTotal',
                                        primary,
                                      ),
                                      const SizedBox(width: 8),
                                      _slotChip(
                                        Icons.two_wheeler,
                                        'Motor',
                                        '$motorAvail/$motorTotal',
                                        primary,
                                      ),
                                      const SizedBox(width: 8),
                                      _slotChip(
                                        Icons.ev_station_rounded,
                                        'EV Charge',
                                        '$evAvail/$evTotal',
                                        const Color(0xFF0284C7),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(0, 32),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                      ),
                                      onPressed: () => widget.args.openEvBook
                                          ?.call(loc['id'] as String),
                                      icon: const Icon(
                                        Icons.bolt_rounded,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Book EV di sini',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
        const SizedBox(height: 14),
        CapacityCard(service),
      ],
    );
  }

  Widget _slotChip(IconData icon, String label, String count, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                count,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );

  /// Replaces Parkee's "Saran Lokasi" section with time-gated Promos managed by Pengelola.
  Widget _promosSection(BuildContext context, RemoteService service) {
    final promos = service.promos;
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Promo Parkir Aktif',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${promos.length} promo',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (promos.isEmpty)
          const SurfaceCard(
            child: EmptyState(
              title: 'Belum ada promo aktif',
              description:
                  'Promo terbatas dari pengelola lokasi parkir akan tampil otomatis di sini.',
            ),
          )
        else
          SizedBox(
            height: 186,
            child: ListView.separated(
              key: const Key('home-promos-list'),
              scrollDirection: Axis.horizontal,
              itemCount: promos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, idx) {
                final p = promos[idx];
                final isPct = p['discount_type'] == 'PERCENT';
                final badge = isPct
                    ? 'DISKON ${p['discount_value']}%'
                    : 'HEMAT ${money((p['discount_value'] as num?)?.toInt())}';
                return SizedBox(
                  width: 274,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
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
                                          color: primary,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          badge,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          p['location_name'] as String? ??
                                              'QPark',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    p['title'] as String? ?? 'Promo QPark',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    p['description'] as String? ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            color: primary.withValues(alpha: 0.10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 14,
                                  color: primary,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    's/d ${wib(p['ends_at'])}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: primary,
                                    ),
                                  ),
                                ),
                                if ((p['code'] as String? ?? '').isNotEmpty)
                                  Text(
                                    p['code'] as String,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: primary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _desktopHeroBanner(BuildContext context, RemoteService service) {
    final primary = Theme.of(context).colorScheme.primary;
    final darkShade = Color.lerp(primary, Colors.black, 0.24)!;
    final greeting = service.customerIdentity?.displayName ?? 'Pengguna QPark';
    final hasActiveTicket =
        service.ticket != null && service.ticket!['state'] != 'COMPLETED';
    final activeEvCount = service.evBookings
        .where((b) => b['status'] == 'ACTIVE')
        .length;

    Widget actionPill(
      Key key,
      String label,
      IconData icon,
      VoidCallback onTap,
    ) {
      return Material(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [darkShade, primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'QPARK · SMART PARKING & EV',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        hasActiveTicket
                            ? 'Tiket Aktif'
                            : '$activeEvCount EV Aktif',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Halo, $greeting',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Parkir lebih mudah',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    actionPill(
                      const Key('quick-book-ev'),
                      'Book EV',
                      Icons.ev_station_rounded,
                      () => widget.args.openEvBook?.call(),
                    ),
                    actionPill(
                      const Key('quick-vehicle'),
                      'Kendaraan',
                      Icons.directions_car_outlined,
                      () => edit(),
                    ),
                    actionPill(
                      const Key('quick-topup'),
                      'Top Up',
                      Icons.add_card_rounded,
                      () => widget.args.navigate(2),
                    ),
                    actionPill(
                      const Key('quick-qr'),
                      'QR Bayar',
                      Icons.qr_code_scanner_rounded,
                      () => widget.args.openQrPay?.call(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 4,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                key: const Key('home-wallet-card'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => widget.args.navigate(2),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.account_balance_wallet_rounded,
                              color: primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
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
                          Icon(Icons.chevron_right_rounded, color: primary),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Saldo tersedia',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        money(service.walletBalance),
                        key: const Key('home-wallet-balance'),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopLocationsGrid(BuildContext context, RemoteService service) {
    final locs = service.locations;
    if (locs.isEmpty) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;
    final selectedId =
        service.selectedLocationId ??
        (service.capacity?['location'] as Map?)?['id'] as String? ??
        locs.first['id'] as String?;

    return Column(
      key: const Key('availability-slider'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Ketersediaan Parkir & EV',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${locs.length} lokasi aktif',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 540 ? 2 : 1;
            const gap = 14.0;
            final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: locs.map((loc) {
                final isSelected = loc['id'] == selectedId;
                final cats = loc['categories'] as Map?;
                final carAvail =
                    (cats?['MOBIL']?['available'] as num?)?.toInt() ?? 0;
                final carTotal =
                    (cats?['MOBIL']?['total'] as num?)?.toInt() ?? 0;
                final motorAvail =
                    (cats?['MOTOR']?['available'] as num?)?.toInt() ?? 0;
                final motorTotal =
                    (cats?['MOTOR']?['total'] as num?)?.toInt() ?? 0;
                final ev = loc['ev'] as Map?;
                final evAvail = (ev?['available'] as num?)?.toInt() ?? 0;
                final evTotal = (ev?['total'] as num?)?.toInt() ?? 0;

                return SizedBox(
                  width: cardW,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: Key('location-card-${loc['id']}'),
                      onTap: () => service.selectLocation(loc['id'] as String),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? primary
                                : Theme.of(context).dividerColor,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              color: isSelected
                                  ? primary
                                  : primary.withValues(alpha: 0.10),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.location_on_rounded,
                                    size: 16,
                                    color: isSelected ? Colors.white : primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      loc['name'] as String? ?? 'Lokasi QPark',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    isSelected ? 'DIPILIH' : 'LIVE',
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : primary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if ((loc['address'] as String? ?? '')
                                      .isNotEmpty)
                                    Text(
                                      loc['address'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _slotChip(
                                        Icons.directions_car,
                                        'Mobil',
                                        '$carAvail/$carTotal',
                                        primary,
                                      ),
                                      const SizedBox(width: 8),
                                      _slotChip(
                                        Icons.two_wheeler,
                                        'Motor',
                                        '$motorAvail/$motorTotal',
                                        primary,
                                      ),
                                      const SizedBox(width: 8),
                                      _slotChip(
                                        Icons.ev_station_rounded,
                                        'EV Charge',
                                        '$evAvail/$evTotal',
                                        const Color(0xFF0284C7),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(0, 34),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                      ),
                                      onPressed: () => widget.args.openEvBook
                                          ?.call(loc['id'] as String),
                                      icon: const Icon(
                                        Icons.bolt_rounded,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Book EV di sini',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _desktopPromosGrid(BuildContext context, RemoteService service) {
    final promos = service.promos;
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Promo Parkir Aktif',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${promos.length} promo berlaku',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (promos.isEmpty)
          const SurfaceCard(
            child: EmptyState(
              title: 'Belum ada promo aktif',
              description:
                  'Promo terbatas dari pengelola lokasi parkir akan tampil otomatis di sini.',
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 540 ? 2 : 1;
              const gap = 14.0;
              final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                key: const Key('home-promos-list'),
                spacing: gap,
                runSpacing: gap,
                children: promos.map((p) {
                  final isPct = p['discount_type'] == 'PERCENT';
                  final badge = isPct
                      ? 'DISKON ${p['discount_value']}%'
                      : 'HEMAT ${money((p['discount_value'] as num?)?.toInt())}';
                  return SizedBox(
                    width: cardW,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                10,
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
                                          color: primary,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          badge,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          p['location_name'] as String? ??
                                              'QPark',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    p['title'] as String? ?? 'Promo QPark',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    p['description'] as String? ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              color: primary.withValues(alpha: 0.10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: primary,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      's/d ${wib(p['ends_at'])}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: primary,
                                      ),
                                    ),
                                  ),
                                  if ((p['code'] as String? ?? '').isNotEmpty)
                                    Text(
                                      p['code'] as String,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: primary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
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

    Widget statusCard() => SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_parking_rounded,
                color: Theme.of(context).colorScheme.primary,
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
                    (status.action == CustomerAction.refresh && service.syncing)
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
    );

    Widget myVehiclesCard() => SurfaceCard(
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
                  'Ketuk Tambah, lalu isi nopol. Centang plat biru untuk EV Charging.',
            ),
          ...service.plates.map((p) {
            final isEv = service.evPlates[p] == true;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: service.selected == p
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.12)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  onTap: () => service.selectPlate(p),
                  leading: Icon(
                    service.selected == p
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          p,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (isEv) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D4ED8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PLAT BIRU',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
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
                          if (context.mounted) {
                            remoteError(context, e);
                          }
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
            );
          }),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 900;
        if (wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _desktopHeroBanner(context, service),
              const SizedBox(height: 24),
              if (service.plates.isNotEmpty) ...[
                VehicleGallery(service: service, onDetails: openDetails),
                const SizedBox(height: 20),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _desktopLocationsGrid(context, service),
                        const SizedBox(height: 24),
                        _desktopPromosGrid(context, service),
                        const SizedBox(height: 24),
                        myVehiclesCard(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        statusCard(),
                        const SizedBox(height: 20),
                        if (service.selected != null) ...[
                          SurfaceCard(
                            key: const Key('desktop-ticket-panel'),
                            child: CustomerTicketDetails(
                              args: widget.args,
                              active: widget.active,
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        CapacityCard(service),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          );
        }

        final mobileContent = Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.fullBleed ? 16 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _quickActions(context),
              const SizedBox(height: 18),
              if (service.plates.isNotEmpty) ...[
                VehicleGallery(service: service, onDetails: openDetails),
                const SizedBox(height: 18),
              ],
              _availabilityAutoSlider(context, service),
              const SizedBox(height: 20),
              _promosSection(context, service),
              const SizedBox(height: 20),
              statusCard(),
              const SizedBox(height: 20),
              myVehiclesCard(),
              const SizedBox(height: 24),
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heroHeader(context, service),
            const SizedBox(height: 40),
            mobileContent,
          ],
        );
      },
    );
  }
}
