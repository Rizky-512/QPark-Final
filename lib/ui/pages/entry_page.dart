import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../common.dart';
import '../remote_common.dart';
import '../widgets/customer_link.dart';

class EntryPage extends StatefulWidget {
  const EntryPage({super.key, required this.args});
  final RemoteArgs args;
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage>
    with AutomaticKeepAliveClientMixin {
  final plate = TextEditingController();
  Uint8List? photo;
  String source = 'test_photo';
  String? vehicleType;
  String? registeredType, resolvedPlate, lookupError;
  bool lookingUp = false;
  Timer? lookupTimer;
  int lookupEpoch = 0;
  String get normalizedPlate =>
      plate.text.toUpperCase().replaceAll(RegExp(r'\s+'), '');

  void changedPlate(String _) {
    lookupTimer?.cancel();
    final epoch = ++lookupEpoch;
    setState(() {
      verified = false;
      registeredType = null;
      vehicleType = null;
      resolvedPlate = null;
      lookupError = null;
      lookingUp = normalizedPlate.isNotEmpty;
    });
    if (normalizedPlate.isEmpty) return;
    lookupTimer = Timer(
      const Duration(milliseconds: 350),
      () => lookupType(epoch),
    );
  }

  Future<void> lookupType(int epoch) async {
    final value = normalizedPlate;
    final token = widget.args.service.token;
    try {
      final r = await widget.args.service.repository.request(
        'GET',
        '/api/officer/vehicle-type?plate=${Uri.encodeComponent(value)}',
        token: token,
      );
      if (!mounted ||
          epoch != lookupEpoch ||
          token != widget.args.service.token) {
        return;
      }
      setState(() {
        registeredType = r['vehicle_type'] as String?;
        resolvedPlate = value;
        lookingUp = false;
      });
    } catch (_) {
      if (!mounted || epoch != lookupEpoch) return;
      setState(() {
        lookingUp = false;
        lookupError = 'Kategori belum dapat diperiksa. Coba lagi.';
      });
    }
  }

  bool readable = false, verified = false, busy = false, manual = true;
  @override
  bool get wantKeepAlive => true;
  @override
  void dispose() {
    lookupTimer?.cancel();
    lookupEpoch++;
    plate.dispose();
    super.dispose();
  }

  Future<void> pick(ImageSource kind) async {
    try {
      final image = await ImagePicker().pickImage(
        source: kind,
        maxWidth: 1400,
        imageQuality: 85,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      if (mounted) {
        setState(() {
          photo = bytes;
          source = kind == ImageSource.camera ? 'camera' : 'test_photo';
          readable = false;
          verified = false;
        });
      }
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          'Gambar belum dapat dibuka. Izinkan akses kamera atau pilih foto uji.',
          error: true,
        );
      }
    }
  }

  Future<void> save() async {
    if (busy ||
        (registeredType ?? vehicleType) == null ||
        resolvedPlate != normalizedPlate ||
        lookingUp ||
        (!manual && (photo == null || !readable)) ||
        !verified) {
      return;
    }
    setState(() => busy = true);
    try {
      final r = await widget.args.service.post('/api/officer/entry', {
        'plate': plate.text,
        'vehicle_type': registeredType ?? vehicleType,
        'verified': verified,
        'image_readable': manual ? false : readable,
        'image_source': manual ? 'manual' : source,
      }, idempotent: true);
      if (!mounted) return;
      setState(() {
        photo = null;
        readable = false;
        verified = false;
        plate.clear();
        registeredType = null;
        resolvedPlate = null;
        lookupEpoch++;
      });
      showMessage(
        context,
        'Kendaraan diterima. Tiket ${r['session']['plate']} sudah tersedia.',
      );
    } catch (e) {
      if (mounted) remoteError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = widget.args.service;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading(
          'Kendaraan masuk',
          'Isi nopol. Kategori tersimpan digunakan otomatis; kendaraan baru memilih jalur masuk mobil atau motor.',
        ),
        CapacityCard(s),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('entry-plate'),
                  controller: plate,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: changedPlate,
                  decoration: const InputDecoration(
                    labelText: 'Nomor polisi',
                    hintText: 'B 1234 AB',
                    helperText:
                        'Baca dari kendaraan, lalu cocokkan sebelum diterima.',
                    helperMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 12),
                if (lookingUp) const LinearProgressIndicator(),
                if (lookupError != null)
                  TextButton.icon(
                    onPressed: () => changedPlate(plate.text),
                    icon: const Icon(Icons.refresh),
                    label: Text(lookupError!),
                  ),
                if (registeredType != null)
                  Text(
                    'Kategori tersimpan: ${registeredType == 'MOTOR' ? 'Motor' : 'Mobil'}',
                    key: const Key('entry-known-category'),
                  )
                else if (resolvedPlate == normalizedPlate &&
                    normalizedPlate.isNotEmpty)
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final kind in ['MOBIL', 'MOTOR'])
                        ChoiceChip(
                          key: ValueKey('entry-type-$kind'),
                          label: Text(
                            kind == 'MOBIL' ? 'Masuk Mobil' : 'Masuk Motor',
                          ),
                          selected: vehicleType == kind,
                          onSelected: busy
                              ? null
                              : (_) => setState(() => vehicleType = kind),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gunakan gambar kendaraan'),
                  subtitle: const Text(
                    'Opsional. Input manual tetap memerlukan verifikasi petugas.',
                  ),
                  value: !manual,
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          manual = !v;
                          verified = false;
                        }),
                ),
                if (!manual) ...[
                  const Text(
                    'Gambar kendaraan',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 210,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.successBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: photo == null
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_a_photo_outlined,
                                  size: 42,
                                  color: AppColors.accent,
                                ),
                                SizedBox(height: 12),
                                Text('Pilih foto uji atau ambil gambar'),
                              ],
                            ),
                          )
                        : Image.memory(
                            photo!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Center(
                              child: Text(
                                'Gambar tidak dapat dibaca. Pilih ulang.',
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  StatusPill(
                    source == 'test_photo'
                        ? 'Foto uji · simulasi kamera'
                        : 'Gambar dari kamera perangkat',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Pilih foto uji'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => pick(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Ambil gambar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                if (!manual)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: readable,
                    onChanged: (!manual && photo == null) || busy
                        ? null
                        : (v) => setState(() => readable = v!),
                    title: const Text('Gambar terbaca dengan jelas'),
                  ),
                CheckboxListTile(
                  key: const Key('entry-verify'),
                  contentPadding: EdgeInsets.zero,
                  value: verified,
                  onChanged: (!manual && photo == null) || busy
                      ? null
                      : (v) => setState(() => verified = v!),
                  title: const Text(
                    'Saya telah mencocokkan nopol dan memastikan kendaraan benar-benar ada',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('entry-save'),
                  onPressed:
                      busy ||
                          !s.online ||
                          (registeredType ?? vehicleType) == null ||
                          lookingUp ||
                          resolvedPlate != normalizedPlate ||
                          (!manual && (photo == null || !readable)) ||
                          !verified ||
                          plate.text.trim().isEmpty ||
                          s.capacity?['categories']?[registeredType ??
                                  vehicleType]?['full'] ==
                              true
                      ? null
                      : save,
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(
                    busy
                        ? 'Menyimpan…'
                        : s.capacity?['categories']?[registeredType ??
                                  vehicleType]?['full'] ==
                              true
                        ? 'Penuh · kendaraan ditolak'
                        : 'Verifikasi & terima kendaraan',
                  ),
                ),
                const SizedBox(height: 12),
                if (!manual)
                  const Text(
                    'Gambar hanya digunakan untuk verifikasi saat ini dan tidak dikirim atau disimpan permanen.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        StaffCustomerLink(service: s),
      ],
    );
  }
}
