import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../domain/errors.dart';
import '../../logic/remote_service.dart';
import '../common.dart';
import '../remote_common.dart';
import 'login_page.dart';

class CustomerLoginPage extends StatefulWidget {
  const CustomerLoginPage({super.key, required this.service});
  final RemoteService service;
  @override
  State<CustomerLoginPage> createState() => _CustomerLoginPageState();
}

class _CustomerLoginPageState extends State<CustomerLoginPage> {
  bool busy = false;
  String? error;
  Future<void> google() async {
    var navigationStarted = false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.loginCustomerGoogle();
      navigationStarted = kIsWeb;
    } catch (e) {
      if (mounted) {
        setState(() => error = e is QParkException ? e.message : e.toString());
      }
    } finally {
      if (mounted && navigationStarted) {
        // A successful web launch unloads this page. If navigation is blocked,
        // restore the button and present a useful retry message.
        Timer(const Duration(seconds: 15), () {
          if (!mounted) return;
          setState(() {
            busy = false;
            error =
                'Halaman Google belum terbuka. Coba lagi atau nonaktifkan pemblokir pop-up untuk situs ini.';
          });
        });
      } else if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void staff() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Akses pengelola & petugas')),
          body: LoginPage(
            service: widget.service,
            onLogin: () => Navigator.pop(context),
          ),
        ),
      ),
    );
  }

  Widget form() => SurfaceCard(
    padding: 28,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          children: [
            Icon(
              Icons.local_parking_rounded,
              size: 34,
              color: AppColors.primary,
            ),
            SizedBox(width: 8),
            Text(
              'QPark',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          'Login customer',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        const Text(
          'Kelola kendaraan, lihat tiket, dan selesaikan pembayaran parkir.',
          style: TextStyle(color: AppColors.muted, height: 1.6),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: const Key('customer-google'),
          onPressed: !busy && widget.service.customerAuth.googleAvailable
              ? google
              : null,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.account_circle_outlined),
          label: Text(busy ? 'Membuka Google…' : 'Masuk dengan Google'),
        ),
        const SizedBox(height: 8),
        Text(
          widget.service.customerAuth.googleAvailable
              ? 'Daftar kendaraan dapat digunakan kembali saat masuk dengan akun yang sama.'
              : 'Login Google belum tersedia. Anda tetap dapat mencoba mode demo.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          key: const Key('customer-demo'),
          onPressed: busy ? null : widget.service.enterCustomerDemo,
          icon: const Icon(Icons.directions_car_outlined),
          label: const Text('Coba sebagai customer demo'),
        ),
        const SizedBox(height: 10),
        const Text(
          'Akses demo tanpa akun. Daftar nopol disimpan pada perangkat ini.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5),
        ),
        if (widget.service.sessionNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              widget.service.sessionNotice!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('officer-login'),
          onPressed: busy ? null : staff,
          icon: const Icon(Icons.badge_outlined),
          label: const Text('Login pengelola / petugas'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('QPark | Ketersediaan parkir')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Cek slot, tanpa perlu login',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Lihat sisa tempat mobil dan motor sebelum menuju area parkir.',
                ),
                const SizedBox(height: 20),
                CapacityCard(widget.service),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: widget.service.syncing
                        ? null
                        : widget.service.sync,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Perbarui slot'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Login opsional untuk menyimpan kendaraan dan mengakses tiket pribadi.',
                ),
                const SizedBox(height: 16),
                form(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
