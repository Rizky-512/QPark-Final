import 'package:flutter/material.dart';
import '../../data/remote_repository.dart';
import '../common.dart';
import '../remote_common.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.args});
  final RemoteArgs args;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final capacity = TextEditingController(),
      car = TextEditingController(),
      motor = TextEditingController(),
      username = TextEditingController(),
      password = TextEditingController();
  List<Json> users = [];
  String role = 'PETUGAS';
  bool active = true, busy = false, editing = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in [capacity, car, motor, username, password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    final s = widget.args.service;
    setState(() => busy = true);
    try {
      final r = await s.repository.request(
        'GET',
        '/api/admin/settings',
        token: s.token,
      );
      final u = await s.repository.request(
        'GET',
        '/api/admin/users',
        token: s.token,
      );
      if (!mounted) return;
      setState(() {
        capacity.text = '${r['settings']['capacity']}';
        car.text = '${r['settings']['car_rate']}';
        motor.text = '${r['settings']['motor_rate']}';
        users = (u['users'] as List).cast<Json>();
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveSettings() async {
    setState(() => busy = true);
    try {
      await widget.args.service.post('/api/admin/settings', {
        'capacity': int.tryParse(capacity.text),
        'car_rate': int.tryParse(car.text),
        'motor_rate': int.tryParse(motor.text),
      });
      if (mounted) {
        showMessage(
          context,
          'Pengaturan disimpan. Tarif baru berlaku untuk kendaraan yang masuk berikutnya.',
        );
      }
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void clearForm() {
    setState(() {
      editing = false;
      username.clear();
      password.clear();
      role = 'PETUGAS';
      active = true;
    });
  }

  Future<void> saveUser() async {
    setState(() => busy = true);
    try {
      await widget.args.service.post('/api/admin/users', {
        'username': username.text,
        'password': password.text,
        'role': role,
        'active': active,
      }, idempotent: true);
      if (!mounted) return;
      clearForm();
      await load();
      if (mounted) {
        showMessage(
          context,
          'Akun disimpan. Perubahan password/peran akan mencabut sesi akun tersebut.',
        );
      }
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PageHeading(
        'Kelola parkir',
        'Pengaturan area dan akun admin/petugas.',
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Text(error!, style: const TextStyle(color: AppColors.danger)),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tarif & kapasitas',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Kapasitas gabungan kendaraan',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: car,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Tarif mobil per jam (Rp)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motor,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Tarif motor per jam (Rp)',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sesi aktif tetap menggunakan tarif ketika kendaraan masuk. Kapasitas tidak boleh lebih kecil dari jumlah kendaraan aktif.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy || !widget.args.service.online
                  ? null
                  : saveSettings,
              child: const Text('Simpan pengaturan'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              editing ? 'Ubah akun' : 'Tambah akun',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: username,
              enabled: !editing && !busy,
              decoration: const InputDecoration(labelText: 'Username akun'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: editing
                    ? 'Password baru (kosong = tetap)'
                    : 'Password akun (minimal 8 karakter)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(role),
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Peran'),
              items: const [
                DropdownMenuItem(value: 'PETUGAS', child: Text('Petugas')),
                DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
              ],
              onChanged: busy ? null : (v) => setState(() => role = v!),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Akun aktif'),
              value: active,
              onChanged: busy ? null : (v) => setState(() => active = v),
            ),
            FilledButton(
              onPressed: busy || !widget.args.service.online ? null : saveUser,
              child: const Text('Simpan akun'),
            ),
            if (editing)
              TextButton(
                onPressed: busy ? null : clearForm,
                child: const Text('Batal edit'),
              ),
            const Divider(),
            ...users.map(
              (u) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(u['username'] as String),
                subtitle: Text(
                  '${u['role']} · ${u['active'] == 1 ? 'Aktif' : 'Nonaktif'}',
                ),
                trailing: IconButton(
                  tooltip: 'Ubah ${u['username']}',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          editing = true;
                          username.text = u['username'] as String;
                          password.clear();
                          role = u['role'] as String;
                          active = u['active'] == 1;
                        }),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
