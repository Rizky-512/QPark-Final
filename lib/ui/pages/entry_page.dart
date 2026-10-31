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
  String vehicleType = 'MOBIL';
  bool readable = false, verified = false, busy = false, manual = true;
  @override
  bool get wantKeepAlive => true;
  @override
  void dispose() {
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
    if (busy || (!manual && (photo == null || !readable)) || !verified) return;
    setState(() => busy = true);
    try {
      final r = await widget.args.service.post('/api/officer/entry', {
        'plate': plate.text,
        'vehicle_type': vehicleType,
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
          'Input nopol dan jenis kendaraan, lalu verifikasi kendaraan yang datang.',
        ),
        CapacityCard(s),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: vehicleType,
                  decoration: const InputDecoration(
                    labelText: 'Jenis kendaraan',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'MOBIL', child: Text('Mobil')),
                    DropdownMenuItem(value: 'MOTOR', child: Text('Motor')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          vehicleType = v!;
                          verified = false;
                        }),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('entry-plate'),
                  controller: plate,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() => verified = false),
                  decoration: const InputDecoration(
                    labelText: 'Nomor polisi',
                    hintText: 'B 1234 AB',
                    helperText:
                        'Baca dari kendaraan, lalu cocokkan sebelum diterima.',
                    helperMaxLines: 3,
                  ),
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
                          (!manual && (photo == null || !readable)) ||
                          !verified ||
                          plate.text.trim().isEmpty ||
                          s.capacity?['full'] == true
                      ? null
                      : save,
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(
                    busy
                        ? 'Menyimpan…'
                        : s.capacity?['full'] == true
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
