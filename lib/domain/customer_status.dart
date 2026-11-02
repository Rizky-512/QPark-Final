import '../data/remote_repository.dart';

enum CustomerAction {
  addVehicle,
  refresh,
  link,
  payment,
  exitQr,
  history,
  reconcile,
}

class CustomerStatus {
  const CustomerStatus(this.title, this.description, this.action, this.label);
  final String title, description, label;
  final CustomerAction action;

  static CustomerStatus resolve({
    required bool hasVehicle,
    required bool online,
    required bool loading,
    required bool pending,
    required Json? ticket,
    required double now,
  }) {
    if (!hasVehicle) {
      return const CustomerStatus(
        'Tambahkan kendaraan',
        'Simpan nopol kendaraan yang Anda gunakan.',
        CustomerAction.addVehicle,
        'Tambah kendaraan',
      );
    }
    if (!online) {
      return CustomerStatus(
        loading ? 'Memuat status parkir' : 'Koneksi terputus',
        loading
            ? 'Sedang memeriksa data terbaru.'
            : 'Data yang tersimpan mungkin sudah berubah. Sambungkan kembali untuk memeriksa tiket.',
        CustomerAction.refresh,
        'Coba lagi',
      );
    }
    if (pending) {
      return const CustomerStatus(
        'Hasil transaksi belum terkonfirmasi',
        'Periksa operasi sebelumnya sebelum melakukan pembayaran lagi.',
        CustomerAction.reconcile,
        'Periksa transaksi',
      );
    }
    if (ticket == null) {
      return const CustomerStatus(
        'Tiket belum terhubung',
        'Kendaraan mungkin sudah dicatat. Tunjukkan kode penghubung kepada petugas untuk mengakses tiket.',
        CustomerAction.link,
        'Hubungkan tiket',
      );
    }
    if (ticket['state'] == 'COMPLETED') {
      return const CustomerStatus(
        'Parkir selesai',
        'Kendaraan sudah keluar. Bukti pembayaran tersedia pada riwayat.',
        CustomerAction.history,
        'Lihat riwayat & bukti',
      );
    }
    final authorization = ticket['authorization'] as Map?;
    if (ticket['state'] == 'EXIT_AUTHORIZED' &&
        authorization?['expires_at'] is num &&
        (authorization!['expires_at'] as num) > now) {
      return const CustomerStatus(
        'Menunggu kendaraan keluar',
        'Izin sudah diberikan. Ikuti arahan petugas; kapasitas dilepas setelah kendaraan lewat.',
        CustomerAction.exitQr,
        'Lihat status keluar',
      );
    }
    final deadline = (ticket['window'] as Map?)?['deadline'];
    if (ticket['window_status'] == 'VALID' &&
        deadline is num &&
        deadline >= now) {
      return const CustomerStatus(
        'Pembayaran lunas',
        'Tunjukkan QR keluar kepada petugas sebelum batas waktu.',
        CustomerAction.exitQr,
        'Tampilkan QR keluar',
      );
    }
    return CustomerStatus(
      'Kendaraan sedang parkir',
      ticket['window_status'] == 'EXPIRED'
          ? 'Batas keluar terlewati. Periksa tagihan tambahan dari server.'
          : 'Periksa perkiraan biaya dan bayar saat siap meninggalkan area.',
      CustomerAction.payment,
      'Bayar',
    );
  }
}
