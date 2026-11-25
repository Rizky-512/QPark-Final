import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../common.dart';
import '../remote_common.dart';
import 'driver_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.args,
    required this.onStaffLogin,
    required this.onLogout,
  });
  final RemoteArgs args;
  final VoidCallback onStaffLogin;
  final VoidCallback onLogout;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool googleBusy = false;

  Future<void> signInGoogle() async {
    if (googleBusy) return;
    setState(() => googleBusy = true);
    try {
      await widget.args.service.loginCustomerGoogle();
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => googleBusy = false);
    }
  }

  Future<void> pickProfilePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 320,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await widget.args.service.setCustomAvatarBase64(base64Encode(bytes));
      if (mounted) showMessage(context, 'Foto profil diperbarui.');
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          'Foto profil belum dapat dipilih. Pastikan izin galeri aktif.',
          error: true,
        );
      }
    }
  }

  Widget _avatar(BuildContext context) {
    final service = widget.args.service;
    final primary = Theme.of(context).colorScheme.primary;
    final b64 = service.activeCustomAvatarBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 30,
          backgroundImage: MemoryImage(base64Decode(b64)),
        );
      } catch (_) {}
    }
    final url = service.customerIdentity?.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: 30,
        backgroundColor: primary.withValues(alpha: 0.14),
        backgroundImage: NetworkImage(url),
      );
    }
    return CircleAvatar(
      radius: 30,
      backgroundColor: primary.withValues(alpha: 0.14),
      child: Icon(Icons.person_rounded, color: primary, size: 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.args.service;
    final isGoogle = service.canCustomizeAppearance;
    final name = service.customerIdentity?.displayName ?? 'Pengguna QPark';
    final subtitle = isGoogle
        ? 'Akun Google aktif · Kustomisasi tema & profil terbuka'
        : 'Akses langsung tanpa login · Masuk Google untuk tema & foto profil';
    final primary = Theme.of(context).colorScheme.primary;

    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Row(
            children: [
              _avatar(context),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatusPill(
                      service.online ? 'Terhubung ke server' : 'Offline',
                      problem: !service.online,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.palette_outlined, color: primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kustomisasi Tema & Profil',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (!isGoogle)
                    const StatusPill('Khusus Google', pending: true),
                ],
              ),
              const SizedBox(height: 8),
              if (!isGoogle) ...[
                const Text(
                  'Aplikasi inti dapat digunakan langsung tanpa akun. Masuk dengan Google jika ingin mengubah Mode Gelap/Terang, warna tema, dan foto profil.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('account-google-login'),
                  onPressed: googleBusy || !service.customerAuth.googleAvailable
                      ? null
                      : signInGoogle,
                  icon: googleBusy
                      ? const ActionProgress()
                      : const Icon(Icons.account_circle_outlined),
                  label: Text(
                    googleBusy
                        ? 'Membuka Google…'
                        : service.customerAuth.googleAvailable
                        ? 'Masuk dengan Google'
                        : 'Login Google belum dikonfigurasi',
                  ),
                ),
              ] else ...[
                SwitchListTile(
                  key: const Key('theme-dark-toggle'),
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    service.activeDarkMode
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: primary,
                  ),
                  title: const Text('Mode Gelap (Dark Mode)'),
                  subtitle: const Text(
                    'Beralih antara tampilan terang dan gelap',
                  ),
                  value: service.activeDarkMode,
                  onChanged: (v) => service.setDarkMode(v),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Warna Tema Aplikasi',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: qparkThemeColorOptions.map((opt) {
                    final selected = service.activeThemeColorValue == opt.$2;
                    return InkWell(
                      key: Key('theme-color-${opt.$2}'),
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => service.setThemeColor(opt.$2),
                      child: Tooltip(
                        message: opt.$1,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(opt.$2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: selected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('profile-photo-pick'),
                      onPressed: pickProfilePhoto,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Ganti Foto Profil'),
                    ),
                    if (service.activeCustomAvatarBase64 != null)
                      TextButton(
                        onPressed: () => service.setCustomAvatarBase64(null),
                        child: const Text('Reset ke Avatar Google'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Kendaraan Saya',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showVehicleEditorDialog(context, service),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (service.plates.isEmpty)
                const EmptyState(
                  title: 'Belum ada kendaraan',
                  description:
                      'Simpan nomor polisi (dan tandai plat biru jika EV) untuk parkir & Book EV.',
                ),
              ...service.plates.map((p) {
                final isEv = service.evPlates[p] == true;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    service.vehicleTypes[p] == 'MOTOR'
                        ? Icons.two_wheeler
                        : Icons.directions_car,
                    color: isEv ? const Color(0xFF1D4ED8) : primary,
                  ),
                  title: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        p,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (isEv)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D4ED8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PLAT BIRU · EV',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    service.vehicleTypes[p] == 'MOTOR' ? 'Motor' : 'Mobil',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (service.selected == p)
                        const StatusPill('Dipilih')
                      else
                        TextButton(
                          onPressed: () => service.selectPlate(p),
                          child: const Text('Pilih'),
                        ),
                      IconButton(
                        tooltip: 'Edit $p',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () =>
                            showVehicleEditorDialog(context, service, old: p),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pengaturan & Akses',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: primary,
                ),
                title: const Text('Dompet QPark'),
                subtitle: Text('Saldo: ${money(service.walletBalance)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.args.navigate(2),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('account-staff-login'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.badge_outlined, color: primary),
                title: const Text('Login Pengelola / Petugas / Superadmin'),
                subtitle: const Text(
                  'Kelola lokasi parkir, slot konvensional & EV, promo, dan gerbang.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onStaffLogin,
              ),
              if (isGoogle) ...[
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: AppColors.danger),
                  title: const Text(
                    'Keluar dari akun Google',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  subtitle: const Text(
                    'Tema & foto profil kembali ke bawaan QPark.',
                  ),
                  onTap: widget.onLogout,
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth >= 820) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: leftColumn),
              const SizedBox(width: 24),
              Expanded(flex: 6, child: rightColumn),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            leftColumn,
            const SizedBox(height: 16),
            rightColumn,
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
