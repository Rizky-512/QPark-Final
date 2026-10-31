import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../logic/remote_service.dart';
import 'common.dart';
import 'remote_common.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/driver_page.dart';
import 'pages/entry_page.dart';
import 'pages/payment_page.dart';
import 'pages/exit_page.dart';
import 'pages/remote_history_page.dart';
import 'pages/admin_page.dart';
import 'pages/customer_login_page.dart';
import 'pages/analytics_page.dart';

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
          ('Beranda', Icons.space_dashboard_outlined),
          ('Tiket', Icons.receipt_long_outlined),
          ('Riwayat', Icons.history),
        ];
  void navigate(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => index = value);
  }

  Future<void> login() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Akses admin & petugas')),
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

  Widget sidebar() => Container(
    width: 225,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
          child: Text(
            widget.service.officer ? 'KELOLA PARKIR' : 'PARKIR SAYA',
            style: const TextStyle(
              letterSpacing: 1.5,
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
                      vertical: widget.service.admin ? 2 : 4,
                    ),
                    child: Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        key: Key('nav-${d.$1}'),
                        dense: widget.service.admin,
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusPill(
                widget.service.online
                    ? 'Terhubung ke server'
                    : 'Offline / data lama',
                problem: !widget.service.online,
              ),
              const SizedBox(height: 12),
              Text(
                widget.service.username ??
                    widget.service.customerIdentity?.displayName ??
                    'Customer demo',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                '1 area · mobil & motor',
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final service = widget.service, args = RemoteArgs(widget.service, navigate);
    final pages = service.officer
        ? <Widget>[
            DashboardPage(args: args),
            EntryPage(args: args),
            ExitPage(args: args),
            RemoteHistoryPage(args: args, active: index == 3),
            if (service.admin) AdminPage(args: args),
            if (service.admin) AnalyticsPage(args: args, active: index == 5),
          ]
        : <Widget>[
            DriverPage(args: args),
            PaymentPage(args: args),
            RemoteHistoryPage(args: args, active: index == 2),
          ];
    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 1000;
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
              if (service.admin && !wide)
                PopupMenuButton<int>(
                  key: const Key('admin-menu'),
                  tooltip: 'Menu admin',
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
                  label: const Text('Login admin / petugas'),
                ),
              if (!service.officer && !wide)
                IconButton(
                  key: const Key('officer-login'),
                  tooltip: 'Login admin / petugas',
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
                          'Permintaan: ${m.requests}\nGagal: ${m.failures}\nTimeout: ${m.timeouts}\np95 (100 terakhir): ${m.p95Milliseconds} ms\nGagal sinkron berturut-turut: ${service.consecutiveFailures}\nInterval sinkron: ${service.pollDelay.inSeconds} detik\nKode error terakhir: ${m.lastErrorCode ?? "?"}',
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
                                    ? 'Memeriksa?'
                                    : 'Periksa & coba ulang',
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: SafeArea(
                        top: false,
                        child: IndexedStack(
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
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar:
              wide || index >= 4 || MediaQuery.viewInsetsOf(context).bottom > 0
              ? null
              : NavigationBar(
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  selectedIndex: index > 3 ? 0 : index,
                  onDestinationSelected: navigate,
                  destinations: destinations
                      .take(service.officer ? 4 : 3)
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
