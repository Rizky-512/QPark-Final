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
      motorCapacity = TextEditingController(),
      car = TextEditingController(),
      motor = TextEditingController(),
      username = TextEditingController(),
      password = TextEditingController(),
      locName = TextEditingController(),
      locAddress = TextEditingController(),
      locCarCap = TextEditingController(text: '10'),
      locMotorCap = TextEditingController(text: '10'),
      locCarRate = TextEditingController(text: '7000'),
      locMotorRate = TextEditingController(text: '2000');

  List<Json> users = [];
  List<Json> locations = [];
  String? settingsLocationId;
  String? userLocationId;
  String? editingLocationId;
  bool locActive = true;
  String role = 'PETUGAS';
  bool active = true, busy = false, editing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    settingsLocationId = widget.args.service.activeLocationId;
    load();
  }

  @override
  void dispose() {
    for (final c in [
      capacity,
      motorCapacity,
      car,
      motor,
      username,
      password,
      locName,
      locAddress,
      locCarCap,
      locMotorCap,
      locCarRate,
      locMotorRate,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    final s = widget.args.service;
    setState(() => busy = true);
    try {
      final locParam = settingsLocationId;
      final settingsPath = locParam == null
          ? '/api/admin/settings'
          : '/api/admin/settings?location_id=${Uri.encodeComponent(locParam)}';
      final r = await s.repository.request('GET', settingsPath, token: s.token);
      final u = await s.repository.request(
        'GET',
        '/api/admin/users',
        token: s.token,
      );
      List<Json> locs = [];
      try {
        final l = await s.repository.request(
          'GET',
          '/api/admin/locations',
          token: s.token,
        );
        locs = ((l['locations'] as List?) ?? const []).cast<Json>();
      } catch (_) {
        locs = s.locations;
      }
      if (!mounted) return;
      final set = r['settings'] as Json;
      setState(() {
        settingsLocationId =
            set['location_id'] as String? ??
            settingsLocationId ??
            (locs.isNotEmpty ? locs.first['id'] as String : null);
        capacity.text = '${set['car_capacity'] ?? ''}';
        motorCapacity.text = '${set['motor_capacity'] ?? ''}';
        car.text = '${set['car_rate']}';
        motor.text = '${set['motor_rate']}';
        users = (u['users'] as List).cast<Json>();
        locations = locs;
        if (userLocationId == null && locs.isNotEmpty) {
          userLocationId = settingsLocationId ?? locs.first['id'] as String;
        }
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
        if (settingsLocationId != null) 'location_id': settingsLocationId,
        'car_capacity': int.tryParse(capacity.text),
        'motor_capacity': int.tryParse(motorCapacity.text),
        'car_rate': int.tryParse(car.text),
        'motor_rate': int.tryParse(motor.text),
      });
      await load();
      if (mounted) {
        showMessage(
          context,
          'Pengaturan slot & tarif disimpan. Tarif baru berlaku untuk kendaraan masuk berikutnya.',
        );
      }
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void clearLocationForm() {
    setState(() {
      editingLocationId = null;
      locName.clear();
      locAddress.clear();
      locCarCap.text = '10';
      locMotorCap.text = '10';
      locCarRate.text = '7000';
      locMotorRate.text = '2000';
      locActive = true;
    });
  }

  Future<void> saveLocation() async {
    setState(() => busy = true);
    try {
      await widget.args.service.post('/api/admin/locations', {
        if (editingLocationId != null) 'id': editingLocationId,
        'name': locName.text,
        'address': locAddress.text,
        'car_capacity': int.tryParse(locCarCap.text),
        'motor_capacity': int.tryParse(locMotorCap.text),
        'car_rate': int.tryParse(locCarRate.text),
        'motor_rate': int.tryParse(locMotorRate.text),
        'active': locActive,
      }, idempotent: true);
      if (!mounted) return;
      clearLocationForm();
      await load();
      if (mounted) {
        showMessage(context, 'Lokasi parkir berhasil disimpan.');
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
        if (role != 'SUPERADMIN' && userLocationId != null)
          'location_id': userLocationId,
      }, idempotent: true);
      if (!mounted) return;
      clearForm();
      await load();
      if (mounted) {
        showMessage(
          context,
          'Akun disimpan. Perubahan password/peran/lokasi akan mencabut sesi akun tersebut.',
        );
      }
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _roleDisplay(String? r) => switch (r) {
    'SUPERADMIN' => 'Superadmin',
    'ADMIN' => 'Pengelola',
    _ => 'Petugas',
  };

  @override
  Widget build(BuildContext context) {
    final service = widget.args.service;
    final isSuper = service.superadmin;
    final currentLocName =
        locations
            .where((l) => l['id'] == settingsLocationId)
            .map((l) => l['name'] as String)
            .firstOrNull ??
        service.staffLocationName ??
        'Area Parkir';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          isSuper ? 'Kelola semua lokasi' : 'Kelola $currentLocName',
          isSuper
              ? 'Tambah lokasi parkir, atur slot, dan tetapkan akun Pengelola/Petugas per lokasi.'
              : 'Atur luas slot parkir, tarif per jam, dan akun petugas lokasi Anda.',
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: AppColors.danger)),
        if (isSuper) ...[
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  editingLocationId == null
                      ? 'Tambah Lokasi Parkir'
                      : 'Ubah Lokasi Parkir',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('location-name'),
                  controller: locName,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Nama lokasi parkir',
                    hintText: 'Contoh: QPark Mall Barat',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('location-address'),
                  controller: locAddress,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Alamat lokasi',
                    hintText: 'Contoh: Jl. Gatot Subroto No. 12',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: locCarCap,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Slot mobil',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: locMotorCap,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Slot motor',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: locCarRate,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Tarif mobil/jam',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: locMotorRate,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Tarif motor/jam',
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lokasi aktif'),
                  value: locActive,
                  onChanged: busy ? null : (v) => setState(() => locActive = v),
                ),
                FilledButton.icon(
                  key: const Key('location-save'),
                  onPressed: busy || !service.online ? null : saveLocation,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: Text(
                    editingLocationId == null
                        ? 'Simpan lokasi baru'
                        : 'Perbarui lokasi',
                  ),
                ),
                if (editingLocationId != null)
                  TextButton(
                    onPressed: busy ? null : clearLocationForm,
                    child: const Text('Batal ubah lokasi'),
                  ),
                const Divider(),
                ...locations.map((loc) {
                  final cats = loc['categories'] as Map?;
                  final cTotal = cats?['MOBIL']?['total'] ?? 0;
                  final mTotal = cats?['MOTOR']?['total'] ?? 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      loc['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${loc['address'] ?? ''} · Mobil $cTotal · Motor $mTotal · ${loc['active'] == true ? 'Aktif' : 'Nonaktif'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Ubah ${loc['name']}',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              editingLocationId = loc['id'] as String;
                              locName.text = loc['name'] as String;
                              locAddress.text =
                                  (loc['address'] as String?) ?? '';
                              locCarCap.text = '$cTotal';
                              locMotorCap.text = '$mTotal';
                              locCarRate.text =
                                  '${loc['rates']?['MOBIL'] ?? 7000}';
                              locMotorRate.text =
                                  '${loc['rates']?['MOTOR'] ?? 2000}';
                              locActive = loc['active'] == true;
                            }),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Luas Slot & Tarif · $currentLocName',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (isSuper && locations.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('settings-loc-$settingsLocationId'),
                  initialValue:
                      locations.any((l) => l['id'] == settingsLocationId)
                      ? settingsLocationId
                      : locations.first['id'] as String,
                  decoration: const InputDecoration(
                    labelText: 'Pilih lokasi yang diatur',
                  ),
                  items: locations
                      .map(
                        (l) => DropdownMenuItem(
                          value: l['id'] as String,
                          child: Text(l['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (v) {
                          setState(() => settingsLocationId = v);
                          load();
                        },
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: capacity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kapasitas slot mobil',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motorCapacity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kapasitas slot motor',
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
                onPressed: busy || !service.online ? null : saveSettings,
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
                editing
                    ? 'Ubah akun pengelola/petugas'
                    : 'Tambah akun pengelola/petugas',
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
                key: ValueKey('role-$role-$isSuper'),
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Peran'),
                items: [
                  const DropdownMenuItem(
                    value: 'PETUGAS',
                    child: Text('Petugas'),
                  ),
                  const DropdownMenuItem(
                    value: 'ADMIN',
                    child: Text('Pengelola'),
                  ),
                  if (isSuper)
                    const DropdownMenuItem(
                      value: 'SUPERADMIN',
                      child: Text('Superadmin'),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => role = v!),
              ),
              if (isSuper && role != 'SUPERADMIN' && locations.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('user-loc-$userLocationId'),
                  initialValue: locations.any((l) => l['id'] == userLocationId)
                      ? userLocationId
                      : locations.first['id'] as String,
                  decoration: const InputDecoration(
                    labelText: 'Lokasi parkir yang dikelola',
                  ),
                  items: locations
                      .map(
                        (l) => DropdownMenuItem(
                          value: l['id'] as String,
                          child: Text(l['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (v) => setState(() => userLocationId = v),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Akun aktif'),
                value: active,
                onChanged: busy ? null : (v) => setState(() => active = v),
              ),
              FilledButton(
                onPressed: busy || !service.online ? null : saveUser,
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
                    '${_roleDisplay(u['role'] as String?)} · ${u['location_name'] ?? 'Semua lokasi'} · ${u['active'] == 1 ? 'Aktif' : 'Nonaktif'}',
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
                            if (u['location_id'] is String) {
                              userLocationId = u['location_id'] as String;
                            }
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
}
