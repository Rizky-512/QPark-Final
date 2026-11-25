import 'package:flutter/material.dart';
import '../remote_common.dart';
import 'payment_page.dart';
import 'remote_history_page.dart';

/// Combines active ticket/payment flow and parking history in one mobile tab ("Aktivitas").
class ActivityPage extends StatefulWidget {
  const ActivityPage({
    super.key,
    required this.args,
    this.active = true,
    this.initialSubTab = 0,
  });
  final RemoteArgs args;
  final bool active;
  final int initialSubTab;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  late int subTab = widget.initialSubTab;

  @override
  void didUpdateWidget(ActivityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSubTab != widget.initialSubTab) {
      subTab = widget.initialSubTab;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.confirmation_number_outlined),
              label: Text('Tiket Aktif'),
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.history),
              label: Text('Riwayat'),
            ),
          ],
          selected: {subTab},
          onSelectionChanged: (v) => setState(() => subTab = v.first),
        ),
        const SizedBox(height: 16),
        if (subTab == 0)
          PaymentPage(args: widget.args, active: widget.active)
        else
          RemoteHistoryPage(args: widget.args, active: widget.active),
      ],
    );
  }
}
