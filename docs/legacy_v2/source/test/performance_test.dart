import 'package:flutter_test/flutter_test.dart';
import 'package:qpark/domain/models.dart';
import 'support.dart';

void main() {
  test('NFR-02 19 dari 20 operasi <=3 detik pada 1.000 transaksi', () async {
    final f = await Fixture.create();
    try {
      final time = f.now.millisecondsSinceEpoch;
      await f.repo.db.transaction(() async {
        for (var i = 0; i < 1000; i++) {
          await f.repo.db.customStatement(
            '''INSERT INTO transaksi_parkir
          (id_transaksi,nomor_polisi,jenis_kendaraan,waktu_masuk,waktu_keluar,tarif_per_jam_saat_masuk,jam_tertagih,total_biaya,metode_pembayaran,
          uang_diterima,kembalian,status_parkir,status_pembayaran,id_petugas_masuk,id_petugas_keluar)
          VALUES (?,?,'Motor',?,?,2000,1,2000,'Tunai',5000,3000,'Selesai','Lunas',2,2)''',
            ['BENCH-$i', 'B${i}ABC', time, time + 3600000],
          );
        }
      });
      final ops = <String, Future<void> Function()>{
        'dashboard': () async {
          await f.service.dashboard(f.officer);
        },
        'riwayat': () async {
          await f.service.history(
            f.officer,
            HistoryFilter(start: f.now, end: f.now),
          );
        },
        'pendapatan': () async {
          await f.service.revenue(
            f.admin,
            HistoryFilter(start: f.now, end: f.now),
          );
        },
        'masuk_bayar': () async {
          final v = await f.service.enter(f.officer, 'BTEST123', Vehicle.motor);
          await f.service.pay(f.officer, v.id, '5000', 2000);
        },
      };
      for (final op in ops.entries) {
        final times = <int>[];
        for (var i = 0; i < 20; i++) {
          final watch = Stopwatch()..start();
          await op.value();
          watch.stop();
          times.add(watch.elapsedMilliseconds);
        }
        times.sort();
        // ignore: avoid_print
        print(
          'NFR-02 ${op.key}: ${times.where((t) => t <= 3000).length}/20 <=3s; p95=${times[18]}ms; max=${times.last}ms',
        );
        expect(times.where((t) => t <= 3000).length, greaterThanOrEqualTo(19));
      }
    } finally {
      await f.close();
    }
  });
}
