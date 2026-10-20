import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../domain/models.dart';
import '../logic/services.dart';
import 'common.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/entry_page.dart';
import 'pages/payment_page.dart';
import 'pages/history_page.dart';
import 'pages/settings_page.dart';
import 'pages/officers_page.dart';

class QParkApp extends StatefulWidget {
  const QParkApp({super.key, required this.initialize});
  final Future<QParkService> Function() initialize;
  @override
  State<QParkApp> createState() => _QParkAppState();
}

class _QParkAppState extends State<QParkApp> {
  late Future<QParkService> future;
  Session? session;
  @override
  void initState() {
    super.initState();
    future = widget.initialize();
  }

  void retry() {
    final next = widget.initialize();
    setState(() {
      future = next;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'QPark · Kelola Parkir',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    locale: const Locale('id', 'ID'),
    supportedLocales: const [Locale('id', 'ID')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: FutureBuilder<QParkService>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_parking_rounded,
                    color: AppColors.primary,
                    size: 64,
                  ),
                  SizedBox(height: 24),
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Menyiapkan QPark…'),
                  SizedBox(height: 8),
                  Text('Penyiapan pertama mungkin memerlukan beberapa saat.'),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SurfaceCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.danger,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'QPark belum dapat dibuka',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Coba lagi'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        final service = snapshot.data!;
        if (session == null) {
          return LoginPage(
            service: service,
            onLogin: (value) => setState(() => session = value),
          );
        }
        return _Shell(
          key: ValueKey(session!.token),
          service: service,
          session: session!,
          onLogout: () {
            service.logout(session!);
            setState(() => session = null);
          },
        );
      },
    ),
  );
}

class _Shell extends StatefulWidget {
  const _Shell({
    super.key,
    required this.service,
    required this.session,
    required this.onLogout,
  });
  final QParkService service;
  final Session session;
  final VoidCallback onLogout;
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int index = 0, busyCount = 0;
  bool dirty = false;
  bool get busy => busyCount > 0;
  bool get admin => widget.session.user.role == Role.admin;
  List<(String, IconData)> get destinations => admin
      ? const [
          ('Beranda', Icons.space_dashboard_outlined),
          ('Riwayat', Icons.receipt_long_outlined),
          ('Pengaturan', Icons.tune_rounded),
          ('Petugas', Icons.people_outline),
        ]
      : const [
          ('Beranda', Icons.space_dashboard_outlined),
          ('Masuk', Icons.add_circle_outline),
          ('Pembayaran', Icons.payments_outlined),
          ('Riwayat', Icons.receipt_long_outlined),
        ];
  Future<bool> mayLeave({bool logout = false}) async {
    if (busy) {
      showMessage(context, 'Tunggu proses yang sedang berjalan selesai.');
      return false;
    }
    if (!dirty) return true;
    return confirm(
      context,
      title: logout ? 'Keluar dari akun?' : 'Tinggalkan halaman?',
      body:
          'Ada isian yang belum disimpan. Jika dilanjutkan, isian akan dibuang.',
      action: logout ? 'Keluar akun' : 'Buang isian',
    );
  }

  Future<void> navigate(int next) async {
    if (index == next || !await mayLeave() || !mounted) return;
    setState(() {
      index = next;
      dirty = false;
    });
  }

  Future<void> logout() async {
    if (await mayLeave(logout: true) && mounted) widget.onLogout();
  }

  void expire() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onLogout();
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
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, 14),
          child: Text(
            'KELOLA PARKIR',
            style: TextStyle(
              letterSpacing: 1.5,
              fontSize: 11,
              color: AppColors.muted,
            ),
          ),
        ),
        ...destinations.indexed.map(
          (d) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                key: Key('nav-${d.$1}'),
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
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatusPill('Penyimpanan lokal'),
              const SizedBox(height: 12),
              Text(
                widget.session.user.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                widget.session.user.role.label,
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final args = ScreenArgs(
      service: widget.service,
      session: widget.session,
      dirty: (value) {
        if (mounted && dirty != value) setState(() => dirty = value);
      },
      busy: (value) {
        if (mounted) setState(() => busyCount += value ? 1 : -1);
      },
      expire: expire,
      navigate: navigate,
    );
    final pages = admin
        ? <Widget>[
            DashboardPage(args: args),
            HistoryPage(args: args),
            SettingsPage(args: args),
            OfficersPage(args: args),
          ]
        : <Widget>[
            DashboardPage(args: args),
            EntryPage(args: args),
            PaymentPage(args: args),
            HistoryPage(args: args),
          ];
    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 1000;
        return PopScope(
          canPop: !dirty && !busy,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop && await mayLeave() && mounted) {
              setState(() {
                dirty = false;
                index = 0;
              });
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                wide ? destinations[index].$1 : 'QPark',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              actions: [
                if (bounds.maxWidth >= 500)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '${widget.session.user.name} · ${widget.session.user.role.label}',
                    ),
                  ),
                IconButton(
                  key: const Key('logout'),
                  tooltip: 'Keluar akun',
                  onPressed: logout,
                  icon: const Icon(Icons.logout),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: Row(
              children: [
                if (wide) sidebar(),
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      key: ValueKey(index),
                      padding: EdgeInsets.all(wide ? 32 : 16),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: pages[index],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: index,
                    onDestinationSelected: navigate,
                    destinations: destinations.indexed
                        .map(
                          (d) => NavigationDestination(
                            key: Key('nav-${d.$1}'),
                            icon: Icon(d.$2.$2),
                            label: d.$2.$1,
                          ),
                        )
                        .toList(),
                  ),
          ),
        );
      },
    );
  }
}
