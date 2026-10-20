# Traceability SRS v1.0 → Flutter

Acuan: SRS v1.0 dari lampiran dan proyek Python revisi. Lingkup bisnis dipertahankan; target desktop diganti HP/web atas permintaan pengguna. Status **ditambah** berarti implementasi baru dalam Dart/Flutter. Bukti dan keterbatasan aktual ada pada HASIL_PENGUJIAN.md. Path relatif terhadap lib/ kecuali assets/, test/, dan README.

| Kode | Kebutuhan | Implementasi Flutter | Status |
|---|---|---|---|
| FR-01 | Login aktif dan pesan umum | logic/services.dart: login; ui/pages/login_page.dart | ditambah |
| FR-02 | Logout dan penutupan sesi | logic/services.dart: logout; ui/app.dart: mayLeave | ditambah |
| FR-03 | Tambah/aktif/nonaktif petugas | logic/services.dart: createOfficer/setOfficerActive; ui/pages/officers_page.dart | ditambah |
| FR-04 | Peran dan akun nonaktif pada sesi | logic/services.dart: requireUser; data/sqlite_repository.dart: _actor | ditambah |
| FR-05 | Kartu kapasitas/terisi/kosong/status | data/sqlite_repository.dart: dashboard; ui/pages/dashboard_page.dart | ditambah |
| FR-06 | Muat ulang slot setelah perubahan | ui/pages/*: reload; ui/app.dart: navigate | ditambah |
| FR-07 | Daftar aktif dan cari pelat/ID | data/sqlite_repository.dart: active; ui/common.dart: VisitList | ditambah |
| FR-08 | Validasi form masuk | domain/rules.dart: normalizePlate; ui/pages/entry_page.dart | ditambah |
| FR-09 | ID/waktu/tarif/status/petugas saat masuk | data/sqlite_repository.dart: createEntry | ditambah |
| FR-10 | Hasil masuk dan kegagalan jelas | ui/pages/entry_page.dart: save; domain/errors.dart | ditambah |
| FR-11 | Pilih transaksi dan estimasi lengkap | logic/services.dart: quote; ui/pages/payment_page.dart | ditambah |
| FR-12 | Pembulatan jam dan lintas hari | domain/rules.dart: calculateQuote | ditambah |
| FR-13 | Tunai dan kembalian sebelum konfirmasi | domain/rules.dart: parseRupiah; payment_page.dart: changeLabel | ditambah |
| FR-14 | Konfirmasi dan simpan pembayaran atomik | logic/services.dart: pay; data/sqlite_repository.dart: completePayment | ditambah |
| FR-15 | Anti klik ganda, batal, rollback | payment_page.dart: busy/pay; UPDATE bersyarat | ditambah |
| FR-16 | Bukti pembayaran lengkap | ui/common.dart: showReceipt | ditambah |
| FR-17 | Filter riwayat inklusif dan detail | logic/services.dart: history/detail; ui/pages/history_page.dart | ditambah |
| FR-18 | Agregasi pendapatan khusus Admin | logic/services.dart: revenue; data/sqlite_repository.dart: revenue | ditambah |
| FR-19 | Ubah kapasitas valid | logic/services.dart: updateSetting; assets/schema.sql: trigger kapasitas | ditambah |
| FR-20 | Ubah tarif bulat positif; snapshot tetap | logic/services.dart: updateSetting; data/sqlite_repository.dart: createEntry | ditambah |
| BR-01 | Konfigurasi Motor/Mobil; integer valid | domain/rules.dart; assets/schema.sql | ditambah |
| BR-02 | Slot dihitung dari transaksi aktif | data/sqlite_repository.dart: dashboard COUNT aktif | ditambah |
| BR-03 | Penuh ditolak; kapasitas >= aktif | assets/schema.sql: trigger kapasitas | ditambah |
| BR-04 | Pelat kapital tanpa spasi, 3–12 alnum | domain/rules.dart: normalizePlate | ditambah |
| BR-05 | Satu pelat aktif lintas jenis | assets/schema.sql: uq_nomor_polisi_aktif | ditambah |
| BR-06 | Waktu otomatis; tidak mundur | logic/services.dart: clock; domain/rules.dart: calculateQuote | ditambah |
| BR-07 | Ceil per jam, minimum satu jam | domain/rules.dart: calculateQuote | ditambah |
| BR-08 | Tarif disalin saat masuk | data/sqlite_repository.dart: createEntry snapshot | ditambah |
| BR-09 | Tunai integer cukup, kembalian benar | domain/rules.dart: parseRupiah; logic/services.dart: pay | ditambah |
| BR-10 | Aktif→Selesai dan pembayaran atomik | data/sqlite_repository.dart: db.transaction | ditambah |
| BR-11 | Biaya berubah perlu konfirmasi ulang | domain/errors.dart: PriceChanged; ui/pages/payment_page.dart: pay | ditambah |
| BR-12 | Selesai immutable; pendapatan total_biaya | assets/schema.sql: immutable triggers; repository.revenue | ditambah |
| NFR-01 | Indonesia, rupiah, status ikon/teks | ui/common.dart, ui/pages/*; locale id_ID | ditambah |
| NFR-02 | 19/20 <=3 detik, 1.000 transaksi | test/performance_test.dart: 1.000 transaksi, 20 iterasi | ditambah |
| NFR-03 | Hash salt, otorisasi, query parameter | logic/security.dart; requireUser; query berparameter | ditambah |
| NFR-04 | Atomic, anti duplikasi dan melebihi kapasitas | assets/schema.sql; data/sqlite_repository.dart: transaction | ditambah |
| NFR-05 | Persistensi setelah restart | data/connection_native.dart, connection_web.dart | ditambah |
| NFR-06 | 1366×768 tanpa tumpang tindih | ui/app.dart: LayoutBuilder; test/widget_test.dart | ditambah |
| NFR-07 | Pemisahan UI/logika/data dan panduan | lib/domain, logic, data, ui; bootstrap.dart; README.md | ditambah |

## Use case

| UC | Halaman / use case |
|---|---|
| UC-01 | login_page / login |
| UC-02 | dashboard_page / dashboard |
| UC-03 | entry_page / enter |
| UC-04 | payment_page / quote, pay |
| UC-05 | history_page / history, detail, revenue |
| UC-06 | settings_page / updateSetting |
| UC-07 | officers_page / createOfficer, setOfficerActive |
| UC-08 | ui/app.dart / mayLeave, logout |
