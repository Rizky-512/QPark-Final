import 'package:flutter/material.dart';
import '../common.dart';
import '../remote_common.dart';
import 'driver_page.dart';

class AccountPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final service = args.service;
    final name = service.customerIdentity?.displayName ?? 'Customer Demo';
    final subtitle = service.customerIdentity != null
        ? 'Akun Google tersinkron Supabase'
        : 'Mode demo lokal · tersimpan di HP';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.successBackground,
                child: const Icon(
                  Icons.person_rounded,
                  color: AppColors.primary,
                  size: 30,
                ),
              ),
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
                        fontSize: 13,
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
                      'Simpan nomor polisi agar tiket parkir otomatis terdeteksi.',
                ),
              ...service.plates.map(
                (p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    service.vehicleTypes[p] == 'MOTOR'
                        ? Icons.two_wheeler
                        : Icons.directions_car,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    p,
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
              Text(
                'Pengaturan & Akses',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Dompet QPark'),
                subtitle: Text('Saldo: ${money(service.walletBalance)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => args.navigate(2),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.badge_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Login Pengelola / Petugas / Superadmin'),
                subtitle: const Text(
                  'Kelola lokasi parkir, kapasitas slot, tarif, dan gerbang.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onStaffLogin,
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: AppColors.danger),
                title: const Text(
                  'Keluar dari akun',
                  style: TextStyle(color: AppColors.danger),
                ),
                onTap: onLogout,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
