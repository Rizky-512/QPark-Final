import 'package:flutter/material.dart';
import '../../domain/customer_status.dart';
import '../common.dart';
import '../remote_common.dart';
import 'customer_link.dart';
import 'parking_cost_card.dart';
import 'receipt_button.dart';
import 'vehicle_gallery.dart';
import 'vehicle_identity.dart';

CustomerStatus customerStatus(RemoteArgs args) {
  final s = args.service;
  return CustomerStatus.resolve(
    hasVehicle: s.selected != null,
    online: s.online,
    loading: s.syncing && s.error == null,
    pending: s.pending.isNotEmpty,
    ticket: s.ticket,
    now: s.serverNow,
  );
}

Future<void> showCustomerTicketDetails(
  BuildContext context,
  RemoteArgs args,
) async {
  final plate = args.service.selected;
  if (plate == null) return;
  final owner = args.service.operationOwner;
  final reduced = MediaQuery.disableAnimationsOf(context);
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Tutup detail tiket',
      barrierColor: Colors.black38,
      transitionDuration: reduced
          ? Duration.zero
          : const Duration(milliseconds: 280),
      reverseTransitionDuration: reduced
          ? Duration.zero
          : const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondary) => LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth >= 850;
          return Align(
            alignment: wide ? Alignment.centerRight : Alignment.bottomCenter,
            child: SizedBox(
              width: wide ? 460 : bounds.maxWidth,
              height: wide ? bounds.maxHeight : bounds.maxHeight * .92,
              child: Material(
                color: AppColors.background,
                borderRadius: wide
                    ? const BorderRadius.horizontal(left: Radius.circular(28))
                    : const BorderRadius.vertical(top: Radius.circular(28)),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(
                  child: Column(
                    children: [
                      if (!wide)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(left: 20, right: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Detail tiket',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              key: const Key('ticket-detail-close'),
                              tooltip: 'Tutup detail tiket',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          child: ListenableBuilder(
                            listenable: args.service,
                            builder: (context, _) {
                              if (args.service.operationOwner != owner ||
                                  args.service.selected != plate) {
                                return const EmptyState(
                                  title: 'Pilihan kendaraan berubah',
                                  description:
                                      'Tutup panel ini dan buka tiket kendaraan yang dipilih.',
                                );
                              }
                              return CustomerTicketDetails(
                                args: RemoteArgs(args.service, (index) {
                                  Navigator.pop(context);
                                  args.navigate(index);
                                }),
                                hero: true,
                              );
                            },
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
      transitionsBuilder: (context, animation, secondary, child) =>
          MediaQuery.disableAnimationsOf(context)
          ? child
          : FadeTransition(
              opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: MediaQuery.sizeOf(context).width >= 850
                          ? const Offset(.04, 0)
                          : const Offset(0, .04),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: child,
              ),
            ),
    ),
  );
}

class CustomerTicketDetails extends StatelessWidget {
  const CustomerTicketDetails({
    super.key,
    required this.args,
    this.hero = false,
    this.active = true,
  });
  final RemoteArgs args;
  final bool hero, active;
  @override
  Widget build(BuildContext context) {
    final s = args.service, status = customerStatus(args);
    final plate = s.selected;
    if (plate == null) {
      return const EmptyState(
        title: 'Pilih kendaraan',
        description: 'Tambahkan kendaraan untuk mulai.',
      );
    }
    final identity = VehicleIdentity(
      plate: plate,
      vehicleType: s.ticket?['vehicle_type'] as String?,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hero) Hero(tag: vehicleHeroTag(s, plate), child: identity),
        if (hero) const SizedBox(height: 20),
        Text(status.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          status.description,
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        if (s.ticket != null) ...[
          SurfaceCard(child: SessionSummary(s.ticket!)),
          const SizedBox(height: 12),
          if (s.ticket!['state'] != 'COMPLETED')
            ParkingCostCard(session: s.ticket!, service: s, active: active),
          ReceiptButton(session: s.ticket!),
        ],
        if (status.action == CustomerAction.link)
          CustomerLinkCard(
            key: ValueKey('detail-link-${s.operationOwner}:$plate'),
            service: s,
          ),
        if (status.action != CustomerAction.link)
          CustomerTicketAction(args: args),
      ],
    );
  }
}

class CustomerTicketAction extends StatefulWidget {
  const CustomerTicketAction({super.key, required this.args});
  final RemoteArgs args;
  @override
  State<CustomerTicketAction> createState() => _CustomerTicketActionState();
}

class _CustomerTicketActionState extends State<CustomerTicketAction> {
  bool opening = false;
  Future<void> act(CustomerStatus status) async {
    if (opening) return;
    final args = widget.args;
    try {
      switch (status.action) {
        case CustomerAction.link:
          setState(() => opening = true);
          await showCustomerTicketDetails(context, args);
        case CustomerAction.payment || CustomerAction.exitQr:
          args.navigate(1);
        case CustomerAction.history:
          args.navigate(1);
        case CustomerAction.refresh:
          await args.service.sync();
        case CustomerAction.reconcile:
          await args.service.retryPending();
        case CustomerAction.addVehicle:
          break;
      }
    } catch (error) {
      if (mounted) remoteError(context, error);
    } finally {
      if (mounted && opening) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.args.service, status = customerStatus(widget.args);
    if (status.action == CustomerAction.addVehicle) {
      return const SizedBox.shrink();
    }
    return FilledButton.icon(
      key: const Key('ticket-dock-action'),
      onPressed:
          opening ||
              s.retrying ||
              (status.action == CustomerAction.refresh && s.syncing)
          ? null
          : () => act(status),
      icon: Icon(
        status.action == CustomerAction.exitQr
            ? Icons.qr_code
            : Icons.arrow_forward,
      ),
      label: Text(status.label),
    );
  }
}
