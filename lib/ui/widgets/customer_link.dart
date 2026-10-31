import 'package:flutter/material.dart';
import '../../logic/remote_service.dart';
import '../common.dart';
import '../remote_common.dart';

class CustomerLinkCard extends StatefulWidget {
  const CustomerLinkCard({super.key, required this.service});
  final RemoteService service;
  @override
  State<CustomerLinkCard> createState() => _CustomerLinkCardState();
}

class _CustomerLinkCardState extends State<CustomerLinkCard> {
  String? code;
  num? expires;
  bool busy = false;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hubungkan tiket dengan aman',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Tunjukkan kode ini kepada petugas setelah kendaraan dicatat masuk. Petugas mencocokkan nopol lalu menghubungkan tiket Anda.',
        ),
        if (code != null) ...[
          const SizedBox(height: 12),
          SelectableText(
            code!,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('Berlaku sampai ${wib(expires)}. Hanya berikan kepada petugas.'),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final plate = widget.service.selected;
                  if (plate == null) return;
                  setState(() => busy = true);
                  try {
                    final result = await widget.service.post(
                      '/api/customer/code',
                      {'plate': plate},
                    );
                    if (mounted) {
                      setState(() {
                        code = result['code'] as String;
                        expires = result['expires_at'] as num;
                      });
                    }
                  } catch (error) {
                    if (context.mounted) remoteError(context, error);
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          icon: const Icon(Icons.link),
          label: Text(
            busy
                ? 'Menyiapkan kode…'
                : code == null
                ? 'Buat kode untuk petugas'
                : 'Buat kode baru',
          ),
        ),
      ],
    ),
  );
}

class StaffCustomerLink extends StatefulWidget {
  const StaffCustomerLink({super.key, required this.service});
  final RemoteService service;
  @override
  State<StaffCustomerLink> createState() => _StaffCustomerLinkState();
}

class _StaffCustomerLinkState extends State<StaffCustomerLink> {
  final plate = TextEditingController(), code = TextEditingController();
  bool verified = false, busy = false;
  @override
  void dispose() {
    plate.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hubungkan tiket pelanggan',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Setelah kendaraan masuk, minta kode dari Beranda pelanggan. Tiket tanpa kode tetap dapat dilayani manual oleh petugas.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: plate,
          enabled: !busy,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() => verified = false),
          decoration: const InputDecoration(labelText: 'Nopol kendaraan aktif'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: code,
          enabled: !busy,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Kode dari pelanggan'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: verified,
          onChanged: busy
              ? null
              : (value) => setState(() => verified = value ?? false),
          title: const Text(
            'Nopol dan kendaraan sudah dicocokkan dengan pelanggan ini',
          ),
        ),
        FilledButton(
          onPressed: busy || !verified
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await widget.service.post('/api/officer/link', {
                      'plate': plate.text,
                      'code': code.text.trim(),
                      'verified': verified,
                    }, idempotent: true);
                    if (context.mounted) {
                      showMessage(
                        context,
                        'Tiket terhubung. Pelanggan dapat memuat ulang Beranda.',
                      );
                      plate.clear();
                      code.clear();
                      verified = false;
                    }
                  } catch (error) {
                    if (context.mounted) remoteError(context, error);
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? 'Menghubungkan…' : 'Verifikasi & hubungkan tiket'),
        ),
      ],
    ),
  );
}
