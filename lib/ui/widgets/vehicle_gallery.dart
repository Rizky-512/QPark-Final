import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../logic/remote_service.dart';
import '../common.dart';
import '../remote_common.dart';
import 'interactive_card.dart';
import 'vehicle_identity.dart';

String vehicleHeroTag(RemoteService service, String plate) =>
    'vehicle:${service.operationOwner}:$plate';

class VehicleGallery extends StatefulWidget {
  const VehicleGallery({
    super.key,
    required this.service,
    required this.onDetails,
  });
  final RemoteService service;
  final VoidCallback onDetails;
  @override
  State<VehicleGallery> createState() => _VehicleGalleryState();
}

class _VehicleGalleryState extends State<VehicleGallery> {
  late final PageController controller;
  String? displayed;
  int get selectedIndex =>
      math.max(0, widget.service.plates.indexOf(widget.service.selected ?? ''));
  @override
  void initState() {
    super.initState();
    displayed = widget.service.selected;
    controller = PageController(
      initialPage: selectedIndex,
      keepPage: false,
      onAttach: (_) => alignSelection(force: true),
    );
  }

  void alignSelection({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          controller.hasClients &&
          (force || controller.page?.round() != selectedIndex)) {
        controller.jumpToPage(selectedIndex);
      }
    });
  }

  @override
  void didUpdateWidget(covariant VehicleGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (displayed != widget.service.selected) {
      displayed = widget.service.selected;
      alignSelection();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> select(int index) async {
    final plate = widget.service.plates[index];
    if (plate == widget.service.selected) return;
    try {
      await widget.service.selectPlate(plate);
    } catch (error) {
      if (mounted) remoteError(context, error);
    }
  }

  void move(int delta) {
    final next = (selectedIndex + delta).clamp(
      0,
      widget.service.plates.length - 1,
    );
    if (controller.hasClients) {
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.jumpToPage(next);
      } else {
        controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } else {
      select(next);
    }
  }

  Widget card(String plate) {
    final service = widget.service;
    final selected = service.selected == plate;
    final ticket = selected && service.ticket?['plate'] == plate
        ? service.ticket
        : null;
    return Semantics(
      selected: selected,
      label: 'Kendaraan $plate',
      child: InteractiveCard(
        key: ValueKey('vehicle-card-$plate'),
        selected: selected,
        onTap: () {
          if (selected) {
            widget.onDetails();
          } else {
            select(service.plates.indexOf(plate));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selected ? 'Kendaraan dipilih' : 'Pilih kendaraan',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.north_east,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Hero(
                tag: vehicleHeroTag(service, plate),
                child: VehicleIdentity(
                  plate: plate,
                  vehicleType: ticket?['vehicle_type'] as String?,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                selected
                    ? service.syncing && ticket == null
                          ? 'Memeriksa tiket…'
                          : ticket != null
                          ? 'Ketuk untuk melihat tiket'
                          : 'Ketuk untuk menghubungkan tiket'
                    : 'Lihat status setelah dipilih',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plates = widget.service.plates;
    if (plates.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, bounds) {
        final desktop = bounds.maxWidth >= 650;
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final plate in plates)
                    SizedBox(
                      width: plates.length == 1
                          ? bounds.maxWidth
                          : (bounds.maxWidth - 16) / 2,
                      child: card(plate),
                    ),
                ],
              )
            else
              SizedBox(
                height: 320 + math.max(0, textScale - 1) * 180,
                child: PageView.builder(
                  key: const Key('vehicle-carousel'),
                  controller: controller,
                  itemCount: plates.length,
                  onPageChanged: select,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 4,
                    ),
                    child: card(plates[index]),
                  ),
                ),
              ),
            if (plates.length > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const Key('vehicle-previous'),
                    tooltip: 'Kendaraan sebelumnya',
                    onPressed: selectedIndex > 0 ? () => move(-1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Flexible(
                    child: Text(
                      '${selectedIndex + 1} dari ${plates.length} kendaraan',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                  IconButton(
                    key: const Key('vehicle-next'),
                    tooltip: 'Kendaraan berikutnya',
                    onPressed: selectedIndex < plates.length - 1
                        ? () => move(1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
