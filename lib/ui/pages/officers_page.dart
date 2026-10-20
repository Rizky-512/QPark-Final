import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../common.dart';

class OfficersPage extends StatefulWidget {
  const OfficersPage({super.key, required this.args});
  final ScreenArgs args;
  @override
  State<OfficersPage> createState() => _OfficersPageState();
}

class _OfficersPageState extends State<OfficersPage> {
  final name = TextEditingController(),
      username = TextEditingController(),
      password = TextEditingController();
  late Future<List<AppUser>> future;
  bool busy = false, hidden = true;
  @override
  void initState() {
    super.initState();
    future = widget.args.service.officers(widget.args.session);
  }

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  void changed(String _) => widget.args.dirty(
    name.text.isNotEmpty ||
        username.text.isNotEmpty ||
        password.text.isNotEmpty,
  );
  void reload() {
    final next = widget.args.service.officers(widget.args.session);
    setState(() {
      future = next;
    });
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    widget.args.busy(true);
    try {
      await widget.args.service.createOfficer(
        widget.args.session,
        name.text,
        username.text,
        password.text,
      );
      if (!mounted) return;
      name.clear();
      username.clear();
      password.clear();
      widget.args.dirty(false);
      reload();
      showMessage(context, 'Akun petugas berhasil dibuat.');
    } catch (e) {
      if (mounted) widget.args.error(context, e);
    } finally {
      widget.args.busy(false);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggle(AppUser user) async {
    if (busy) return;
    setState(() => busy = true);
    widget.args.busy(true);
    try {
      if (!await confirm(
        context,
        title: '${user.active ? 'Nonaktifkan' : 'Aktifkan'} petugas?',
        body:
            '${user.name} (${user.username})\n${user.active ? 'Akun ini akan ditolak pada tindakan berikutnya, termasuk sesi yang sedang terbuka.' : 'Akun ini dapat masuk kembali.'}',
        action: user.active ? 'Nonaktifkan' : 'Aktifkan',
      )) {
        return;
      }
      await widget.args.service.setOfficerActive(
        widget.args.session,
        user.id,
        !user.active,
      );
      if (mounted) {
        reload();
        showMessage(context, 'Status petugas berhasil diperbarui.');
      }
    } catch (e) {
      if (mounted) widget.args.error(context, e);
    } finally {
      widget.args.busy(false);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PageHeading(
        'Akun petugas',
        'Kelola akses petugas untuk lokasi parkir ini.',
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tambah petugas',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, bounds) {
                final width = bounds.maxWidth >= 900
                    ? (bounds.maxWidth - 32) / 3
                    : bounds.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: width,
                      child: TextField(
                        controller: name,
                        enabled: !busy,
                        onChanged: changed,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nama petugas',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: TextField(
                        controller: username,
                        enabled: !busy,
                        onChanged: changed,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nama pengguna',
                          helperText: 'Disimpan sebagai huruf kecil',
                          helperMaxLines: 2,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: TextField(
                        controller: password,
                        enabled: !busy,
                        obscureText: hidden,
                        onChanged: changed,
                        onSubmitted: (_) => save(),
                        decoration: InputDecoration(
                          labelText: 'Kata sandi',
                          helperText: 'Minimal 8 karakter',
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
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: busy ? null : save,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(busy ? 'Memproses…' : 'Tambah petugas'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      LoadPanel(
        future: future,
        retry: reload,
        onExpired: widget.args.expire,
        builder: (users) => SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Daftar petugas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ...users.map(
                (user) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 190,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              user.username,
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(
                        user.active ? 'Aktif' : 'Nonaktif',
                        problem: !user.active,
                      ),
                      OutlinedButton(
                        onPressed: busy ? null : () => toggle(user),
                        child: Text(user.active ? 'Nonaktifkan' : 'Aktifkan'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
