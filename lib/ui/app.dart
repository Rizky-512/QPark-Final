import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../config.dart';
import '../logic/remote_service.dart';
import 'common.dart';
import 'widgets/page_motion.dart';
import 'widgets/customer_ticket_details.dart';
import 'remote_common.dart';
import 'pages/account_page.dart';
import 'pages/activity_page.dart';
import 'pages/admin_page.dart';
import 'pages/analytics_page.dart';
import 'pages/customer_login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/driver_page.dart';
import 'pages/entry_page.dart';
import 'pages/exit_page.dart';
import 'pages/login_page.dart';
import 'pages/qr_pay_page.dart';
import 'pages/remote_history_page.dart';
import 'pages/wallet_page.dart';

class QParkApp extends StatefulWidget {
  const QParkApp({super.key, required this.initialize});
  final Future<RemoteService> Function() initialize;
  @override
  State<QParkApp> createState() => _QParkAppState();
}

class _QParkAppState extends State<QParkApp> with WidgetsBindingObserver {
  late Future<RemoteService> future;
  RemoteService? service;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    future = initialize();
  }

  Future<RemoteService> initialize() async {
    final value = await widget.initialize();
    service = value;
    value.setForeground(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    value.start();
    return value;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    service?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    service?.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => AppConfig.environment == 'test'
        ? Banner(
            message: 'PENGUJIAN',
            location: BannerLocation.topEnd,
            child: child!,
          )
        : child!,
    title: 'QPark · Parkir lebih mudah',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    locale: const Locale('id', 'ID'),
    supportedLocales: const [Locale('id', 'ID')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: FutureBuilder<RemoteService>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SurfaceCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('QPark belum dapat dibuka.'),
                      Text('${snapshot.error}'),
                      FilledButton(
                        onPressed: () => setState(() => future = initialize()),
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return ListenableBuilder(
          listenable: snapshot.data!,
          builder: (context, _) => !snapshot.data!.signedIn
              ? CustomerLoginPage(service: snapshot.data!)
              : _Shell(
                  key: ValueKey(
                    '${snapshot.data!.role}:${snapshot.data!.operationOwner}',
                  ),
                  service: snapshot.data!,
                ),
        );
      },
    ),
  );
}

class _Shell extends StatefulWidget {
  const _Shell({super.key, required this.service});
  final RemoteService service;
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int index = 0;
  String? checkoutSessionId;
  int checkoutRequest = 0;

  void openCheckout(String sessionId) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      checkoutSessionId = sessionId;
      checkoutRequest++;
      index = 2;
    });
  }

  void openQrPay() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => QrPayPage(
          service: widget.service,
          onOpenWallet: () => navigate(2),
          onOpenActivity: () => navigate(1),
        ),
      ),
    );
  }

  List<(String, IconData)> get destinations => widget.service.officer
      ? [
          ('Beranda', Icons.space_dashboard_outlined),
          ('Masuk', Icons.add_circle_outline),
          ('Keluar', Icons.qr_code_scanner),
          ('Riwayat', Icons.history),
          if (widget.service.admin) ('Kelola', Icons.manage_accounts_outlined),
          if (widget.service.admin) ('Analisis', Icons.bar_chart_rounded),
        ]
      : const [
          ('Home', Icons.home_rounded),
          ('Aktivitas', Icons.receipt_long_rounded),
          ('Dompet', Icons.account_balance_wallet_rounded),
          ('Akun', Icons.person_rounded),
        ];

  void navigate(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (index != value) setState(() => index = value);
  }

  Future<void> login() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Akses pengelola & petugas')),
          body: LoginPage(
            service: widget.service,
            onLogin: () {
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Future<void> logout() async {
    if (await confirm(
      context,
      title: 'Keluar dari akun?',
      body:
          'Kembali ke halaman login. Daftar nopol pada perangkat tetap tersimpan.',
      action: 'Keluar akun',
    )) {
      await widget.service.logout();
    }
  }

  Widget _customerBottomBar() {
    Widget tabItem(int tabIndex, IconData icon, String label) {
      final selected = index == tabIndex;
      return Expanded(
        child: InkWell(
          key: Key('nav-$tabIndex'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => navigate(tabIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? AppColors.primary : AppColors.muted,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? AppColors.primary : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      color: AppColors.surface,
      elevation: 8,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      height: 64,
      child: Row(
        children: [
          tabItem(0, Icons.home_rounded, 'Home'),
          tabItem(1, Icons.receipt_long_rounded, 'Aktivitas'),
          const SizedBox(width: 64),
          tabItem(2, Icons.account_balance_wallet_rounded, 'Dompet'),
          tabItem(3, Icons.person_rounded, 'Akun'),
        ],
      ),
    );
  }

  Widget sidebar() {
    final service = widget.service;
    return Container(
      width: 235,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Icon(
                  Icons.local_parking_rounded,
                  size: 34,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'QPark',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!service.officer)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FilledButton.icon(
                key: const Key('fab-scan-qr'),
                onPressed: openQrPay,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan QR Bayar'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
            child: Text(
              service.officer
                  ? 'KELOLA PARKIR · ${service.roleLabel.toUpperCase()}'
                  : 'PARKIR SAYA',
              style: const TextStyle(
                letterSpacing: 1.3,
                fontSize: 11,
                color: AppColors.muted,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ...destinations.indexed.map(
                    (d) => Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: service.admin ? 2 : 4,
                      ),
                      child: Material(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          key: Key('nav-${d.$1}'),
                          dense: service.admin,
                          selected: index == d.$1,
                          selectedColor: AppColors.primary,
                          selectedTileColor: AppColors.successBackground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Icon(d.$2.$2),
                          title: Text(d.$2.$1),
                          onTap: () => navigate(d.$1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(
                  service.online
                      ? 'Terhubung ke server'
                      : 'Offline / data lama',
                  problem: !service.online,
                ),
                const SizedBox(height: 12),
                Text(
                  service.username ??
                      service.customerIdentity?.displayName ??
                      'Customer demo',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  service.officer
                      ? (service.staffLocationName ??
                            (service.superadmin
                                ? 'Semua lokasi'
                                : 'Area parkir'))
                      : 'Dompet: ${money(service.walletBalance)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final args = RemoteArgs(
      widget.service,
      navigate,
      openCheckout: openCheckout,
      openQrPay: openQrPay,
    );
    final pages = service.officer
        ? <Widget>[
            DashboardPage(args: args),
            EntryPage(args: args),
            ExitPage(
              args: args,
              sessionId: checkoutSessionId,
              requestId: checkoutRequest,
              active: index == 2,
            ),
            RemoteHistoryPage(args: args, active: index == 3),
            if (service.admin) AdminPage(args: args),
            if (service.admin) AnalyticsPage(args: args, active: index == 5),
          ]
        : <Widget>[
            DriverPage(args: args, active: index == 0),
            ActivityPage(args: args, active: index == 1),
            WalletPage(args: args, active: index == 2),
            AccountPage(args: args, onStaffLogin: login, onLogout: logout),
          ];

    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 1000;
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final showCustomerFab = !service.officer && !wide && !keyboardOpen;
        return Scaffold(
          appBar: AppBar(
            leading: !wide && index >= 4
                ? BackButton(
                    key: const Key('back-operations'),
                    onPressed: () => navigate(0),
                  )
                : null,
            title: Text(
              wide
                  ? destinations[index].$1
                  : 'QPark · ${destinations[index].$1}',
              style: const TextStyle(fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (service.superadmin && service.locations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('superadmin-location-switch'),
                      value:
                          service.locations.any(
                            (l) => l['id'] == service.selectedLocationId,
                          )
                          ? service.selectedLocationId
                          : service.locations.first['id'] as String,
                      items: service.locations
                          .map(
                            (l) => DropdownMenuItem(
                              value: l['id'] as String,
                              child: Text(
                                l['name'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => service.selectLocation(v),
                    ),
                  ),
                ),
              if (service.admin && !wide)
                PopupMenuButton<int>(
                  key: const Key('admin-menu'),
                  tooltip: 'Menu pengelola',
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  onSelected: navigate,
                  itemBuilder: (_) => [
                    for (final i in [4, 5])
                      PopupMenuItem(
                        value: i,
                        key: Key('nav-$i'),
                        child: ListTile(
                          leading: Icon(destinations[i].$2),
                          title: Text(destinations[i].$1),
                        ),
                      ),
                  ],
                ),
              IconButton(
                key: const Key('logout'),
                tooltip: 'Keluar akun',
                onPressed: logout,
                icon: const Icon(Icons.logout),
              ),
              if (!service.officer && wide)
                TextButton.icon(
                  key: const Key('officer-login'),
                  onPressed: login,
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Login pengelola / petugas'),
                ),
              if (!service.officer && !wide)
                IconButton(
                  key: const Key('officer-login'),
                  tooltip: 'Login pengelola / petugas',
                  onPressed: login,
                  icon: const Icon(Icons.badge_outlined),
                ),
              if (service.officer)
                IconButton(
                  tooltip: 'Status koneksi',
                  icon: const Icon(Icons.monitor_heart_outlined),
                  onPressed: () {
                    final m = service.repository.metrics;
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Status koneksi sesi ini'),
                        content: Text(
                          'Peran: ${service.roleLabel}\nLokasi: ${service.staffLocationName ?? 'Semua lokasi'}\nPermintaan: ${m.requests}\nGagal: ${m.failures}\nTimeout: ${m.timeouts}\np95 (100 terakhir): ${m.p95Milliseconds} ms\nGagal sinkron berturut-turut: ${service.consecutiveFailures}\nInterval sinkron: ${service.pollDelay.inSeconds} detik\nKode error terakhir: ${m.lastErrorCode ?? "?"}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Tutup'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: Row(
            children: [
              if (wide) sidebar(),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 2,
                      child: service.syncing && service.online
                          ? const LinearProgressIndicator(
                              semanticsLabel: 'Memperbarui data',
                            )
                          : const SizedBox.shrink(),
                    ),
                    if (!service.online)
                      Container(
                        width: double.infinity,
                        color: AppColors.dangerBackground,
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              service.error ?? 'Menghubungkan ke server…',
                              style: const TextStyle(color: AppColors.danger),
                            ),
                            TextButton(
                              onPressed: service.syncing ? null : service.sync,
                              child: const Text('Coba lagi'),
                            ),
                          ],
                        ),
                      ),
                    if (service.customerError != null)
                      Container(
                        width: double.infinity,
                        color: AppColors.dangerBackground,
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              service.customerError!,
                              style: const TextStyle(color: AppColors.danger),
                            ),
                            TextButton(
                              onPressed: service.refreshCustomerData,
                              child: const Text('Muat ulang kendaraan'),
                            ),
                          ],
                        ),
                      ),
                    if (service.pending.isNotEmpty)
                      Container(
                        width: double.infinity,
                        color: AppColors.successBackground,
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            const Text('Ada operasi yang belum terkonfirmasi.'),
                            TextButton(
                              onPressed: service.retrying
                                  ? null
                                  : () async {
                                      try {
                                        await service.retryPending();
                                      } catch (e) {
                                        if (context.mounted) {
                                          remoteError(context, e);
                                        }
                                      }
                                    },
                              child: Text(
                                service.retrying
                                    ? 'Memeriksa…'
                                    : 'Periksa & coba ulang',
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: SafeArea(
                        top: false,
                        child: PageMotion(
                          index: index,
                          children: pages.indexed
                              .map(
                                (p) => SingleChildScrollView(
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  key: PageStorageKey(
                                    'page-${p.$1}-${service.officer}',
                                  ),
                                  padding: EdgeInsets.all(wide ? 32 : 16),
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 1200,
                                      ),
                                      child: p.$2,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    if (!service.officer &&
                        index == 0 &&
                        service.selected != null &&
                        !keyboardOpen)
                      Container(
                        key: const Key('customer-action-dock'),
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          border: Border(
                            top: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          bottom: wide,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: SizedBox(
                                width: double.infinity,
                                child: CustomerTicketAction(args: args),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          floatingActionButton: showCustomerFab
              ? FloatingActionButton(
                  key: const Key('fab-scan-qr'),
                  tooltip: 'Scan QR Bayar',
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: const CircleBorder(),
                  onPressed: openQrPay,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, size: 24),
                      Text(
                        'Pay',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          bottomNavigationBar: wide || keyboardOpen
              ? null
              : !service.officer
              ? _customerBottomBar()
              : index >= 4
              ? null
              : NavigationBar(
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  selectedIndex: index > 3 ? 0 : index,
                  onDestinationSelected: navigate,
                  destinations: destinations
                      .take(4)
                      .indexed
                      .map(
                        (d) => NavigationDestination(
                          key: Key('nav-${d.$1}'),
                          icon: Icon(d.$2.$2),
                          label: d.$2.$1,
                        ),
                      )
                      .toList(),
                ),
        );
      },
    );
  }
}
