import 'package:flutter/material.dart';
import '../common.dart';
import '../remote_common.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key, required this.args, this.active = true});
  final RemoteArgs args;
  final bool active;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final customAmount = TextEditingController();
  bool busy = false;
  int selectedPreset = 50000;

  static const presets = [20000, 50000, 100000, 200000];

  @override
  void initState() {
    super.initState();
    widget.args.service.refreshWallet().catchError((_) {});
  }

  @override
  void dispose() {
    customAmount.dispose();
    super.dispose();
  }

  Future<void> topUp(int amount) async {
    if (busy) return;
    if (amount < 1000 || amount > 10000000) {
      showMessage(
        context,
        'Nominal top up harus antara Rp1.000 hingga Rp10.000.000.',
        error: true,
      );
      return;
    }
    setState(() => busy = true);
    try {
      await widget.args.service.topUpWallet(amount);
      if (!mounted) return;
      customAmount.clear();
      showMessage(
        context,
        'Top up ${money(amount)} berhasil masuk ke Dompet QPark.',
      );
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.args.service;
    final txs = service.walletTransactions;
    final primary = Theme.of(context).colorScheme.primary;
    final darkShade = Color.lerp(primary, Colors.black, 0.2)!;
    final balanceAndTopup = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [darkShade, primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Dompet QPark',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Prototipe',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Saldo tersedia',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                money(service.walletBalance),
                key: const Key('wallet-balance'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Saldo simulasi untuk pembayaran parkir cepat lewat tombol Scan QR.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Top Up Instan (Simulasi)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'Pilih nominal cepat atau ketik nominal sendiri. Tidak memotong uang sungguhan.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets
                    .map(
                      (amount) => ChoiceChip(
                        key: Key('topup-preset-$amount'),
                        label: Text(money(amount)),
                        selected:
                            customAmount.text.isEmpty &&
                            selectedPreset == amount,
                        onSelected: busy
                            ? null
                            : (_) => setState(() {
                                selectedPreset = amount;
                                customAmount.clear();
                              }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('topup-custom'),
                controller: customAmount,
                enabled: !busy,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Nominal lain (opsional, Rp)',
                  hintText: 'Contoh: 75000',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('wallet-topup-submit'),
                onPressed: busy || !service.online
                    ? null
                    : () {
                        final parsed = customAmount.text.trim().isEmpty
                            ? selectedPreset
                            : (int.tryParse(customAmount.text.trim()) ?? 0);
                        topUp(parsed);
                      },
                icon: busy
                    ? const ActionProgress()
                    : const Icon(Icons.add_circle_outline),
                label: Text(
                  busy
                      ? 'Memproses top up…'
                      : 'Top Up ${money(customAmount.text.trim().isEmpty ? selectedPreset : (int.tryParse(customAmount.text.trim()) ?? 0))}',
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final historyCard = SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Riwayat Mutasi',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Muat ulang mutasi',
                onPressed: busy
                    ? null
                    : () => service.refreshWallet().catchError((_) {}),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (txs.isEmpty)
            const EmptyState(
              title: 'Belum ada transaksi dompet',
              description:
                  'Lakukan top up simulasi atau bayar tagihan parkir untuk melihat mutasi.',
            ),
          ...txs.map((tx) {
            final isTopup = tx['kind'] == 'TOPUP';
            final amount = (tx['amount'] as num?)?.toInt() ?? 0;
            final after = (tx['balance_after'] as num?)?.toInt() ?? 0;
            return Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isTopup
                        ? AppColors.successBackground
                        : AppColors.dangerBackground,
                    child: Icon(
                      isTopup
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      color: isTopup ? AppColors.primary : AppColors.danger,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    tx['description'] as String? ??
                        (isTopup ? 'Top up saldo' : 'Pembayaran parkir'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${wib(tx['created_at'])} · Saldo ${money(after)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  trailing: Text(
                    '${isTopup ? '+' : '-'}${money(amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isTopup ? AppColors.primary : AppColors.danger,
                    ),
                  ),
                ),
                const Divider(height: 1),
              ],
            );
          }),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth >= 820) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: balanceAndTopup),
              const SizedBox(width: 24),
              Expanded(flex: 6, child: historyCard),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            balanceAndTopup,
            const SizedBox(height: 20),
            historyCard,
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
