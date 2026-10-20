import 'package:flutter/material.dart';
import '../../domain/errors.dart';
import '../../domain/models.dart';
import '../../logic/services.dart';
import '../common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.service, required this.onLogin});
  final QParkService service;
  final void Function(Session) onLogin;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController(), password = TextEditingController();
  bool busy = false, hidden = true;
  String? error;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = await widget.service.login(username.text, password.text);
      if (mounted) widget.onLogin(session);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is QParkException
              ? e.message
              : 'Login gagal. Silakan coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget form() => SurfaceCard(
    padding: 28,
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_parking_rounded,
                color: AppColors.primary,
                size: 34,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'QPark',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            'Selamat datang',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Masuk untuk mulai mengelola parkir.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 28),
          TextField(
            key: const Key('login-username'),
            controller: username,
            enabled: !busy,
            autofocus: true,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nama pengguna',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('login-password'),
            controller: password,
            enabled: !busy,
            obscureText: hidden,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => login(),
            decoration: InputDecoration(
              labelText: 'Kata sandi',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: hidden
                    ? 'Tampilkan kata sandi'
                    : 'Sembunyikan kata sandi',
                onPressed: () => setState(() => hidden = !hidden),
                icon: Icon(
                  hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                error!,
                key: const Key('login-error'),
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('login-submit'),
            onPressed: busy ? null : login,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(busy ? 'Memeriksa akun…' : 'Masuk'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Data tersimpan pada perangkat ini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: bounds.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Row(
                    children: [
                      if (bounds.maxWidth >= 850)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 70),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.local_parking_rounded,
                                  size: 76,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Parkir tertata.\nPelayanan lebih mudah.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary,
                                      ),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Catat kendaraan, pantau ketersediaan,\ndan selesaikan pembayaran dalam satu tempat.',
                                  style: TextStyle(
                                    fontSize: 17,
                                    height: 1.7,
                                    color: AppColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                const StatusPill(
                                  'Motor & mobil · Pembayaran tunai',
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: Align(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: form(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
