# Traceability SRS v1.0

Acuan dibaca dari `SRS_Prototipe_Aplikasi_Parkir(1).docx` yang dilampirkan, versi 1.0 tanggal 29 September 2026. Semua 20 FR, 12 BR, dan 7 NFR diaudit.

Status **sudah** berarti inti kebutuhan ada sejak kode awal dan dipertahankan; **diperbaiki** berarti ada koreksi atau penguatan; **ditambah** berarti komponen baru. Status implementasi bukan otomatis kelulusan verifikasi native Windows. Semua path singkat di tabel relatif terhadap `app/`, kecuali `tests/`, `scripts/`, `docs/`, dan file root.

| Kode | Kebutuhan | File/fungsi | Status | Bukti/batas verifikasi |
|---|---|---|---|---|
| FR-01 | Login aktif dan pesan umum | logic/services.py: AuthService.login; ui/login_page.py | diperbaiki | AT-01; test_ui_smoke |
| FR-02 | Logout dan penutupan sesi | logic/sessions.py; AuthService.logout; ParkingApp.confirm_leave | diperbaiki | AT-01; tes form/logout |
| FR-03 | Tambah/aktif/nonaktif petugas | AdminService.create_officer/set_officer_active; ui/settings_page.py | sudah | AT-02; username/password |
| FR-04 | Peran dan akun nonaktif pada sesi | SecuredService.require_user; repository.create_entry/finish_transaction | diperbaiki | AT-02; AT-12 sesi nonaktif |
| FR-05 | Kartu kapasitas/terisi/kosong/status | SQLiteParkingRepository.get_slot_summaries; ui/dashboard_page.py | diperbaiki | AT-03/05; tes error UI |
| FR-06 | Muat ulang slot setelah perubahan | ParkingService.dashboard; build_dashboard_page.load | sudah | AT-03/07/11 |
| FR-07 | Daftar aktif dan cari pelat/ID | SQLiteParkingRepository.list_active; common.transaction_table | diperbaiki | AT-10 literal search |
| FR-08 | Validasi form masuk | normalize_plate; ParkingService.record_entry; schema.sql | diperbaiki | AT-04/05 |
| FR-09 | ID/waktu/tarif/status/petugas saat masuk | SQLiteParkingRepository.create_entry | diperbaiki | AT-03; tes rollback masuk |
| FR-10 | Hasil masuk dan kegagalan jelas | ui/entry_page.py; DataAccessError; repository._connect | diperbaiki | AT-03/05/08 |
| FR-11 | Pilih transaksi dan estimasi lengkap | ParkingService.quote_payment; ui/payment_page.py | diperbaiki | AT-06; tes callback pembayaran |
| FR-12 | Pembulatan jam dan lintas hari | ParkingService._calculate_quote | sudah | AT-06; 0/60/61 menit dan tengah malam |
| FR-13 | Tunai dan kembalian sebelum konfirmasi | parse_rupiah; payment_page.update_change | diperbaiki | AT-07; pecahan/format rupiah |
| FR-14 | Konfirmasi dan simpan pembayaran atomik | ParkingService.complete_payment; SQLiteParkingRepository.finish_transaction | diperbaiki | AT-07/08/09 |
| FR-15 | Anti klik ganda, batal, rollback | payment_page.confirm_dialog/complete; UPDATE bersyarat | diperbaiki | AT-08; konkurensi dan callback |
| FR-16 | Bukti pembayaran lengkap | ui/common.py: receipt; payment_page.py | diperbaiki | AT-07; tes bukti UI |
| FR-17 | Filter riwayat inklusif dan detail | ParkingService.history/transaction_detail; repo.list_history; history_page.py | diperbaiki | AT-10; ujung hari dan tanggal maksimal |
| FR-18 | Agregasi pendapatan khusus Admin | AdminService.revenue; repo.revenue_summary; settings_page.py | diperbaiki | AT-02/10 |
| FR-19 | Ubah kapasitas valid | AdminService.update_settings; trigger kapasitas | diperbaiki | AT-11; rollback tarif bersama kapasitas |
| FR-20 | Ubah tarif bulat positif; snapshot tetap | parse_rupiah; AdminService.update_settings; repo.create_entry | diperbaiki | AT-11; tarif baru/lama |
| BR-01 | Konfigurasi Motor/Mobil; integer valid | parse_integer/parse_rupiah; schema.sql CHECK | diperbaiki | AT-05/07/11 |
| BR-02 | Slot dihitung dari transaksi aktif | repo.get_slot_summaries COUNT(Aktif) | sudah | AT-03/05/07 |
| BR-03 | Penuh ditolak; kapasitas >= aktif | schema.sql: trg_kapasitas_saat_masuk/trg_kapasitas_tidak_boleh_di_bawah_aktif | sudah | AT-05/11; konkurensi masuk |
| BR-04 | Pelat kapital tanpa spasi, 3–12 alnum | normalize_plate; schema.sql CHECK | sudah | tes asli normalisasi; AT-04/05 |
| BR-05 | Satu pelat aktif lintas jenis | schema.sql: uq_nomor_polisi_aktif | sudah | tes asli duplikasi; AT-04 |
| BR-06 | Waktu otomatis; tidak mundur | ParkingService.clock/_calculate_quote; repo._iso; schema CHECK | diperbaiki | AT-03/06; presisi dan jam mundur |
| BR-07 | Ceil per jam, minimum satu jam | ParkingService._calculate_quote | sudah | AT-06 |
| BR-08 | Tarif disalin saat masuk | repo.create_entry; trx.tarif_per_jam_saat_masuk | sudah | AT-11 |
| BR-09 | Tunai integer cukup, kembalian benar | parse_rupiah; complete_payment; schema CHECK | diperbaiki | AT-07 |
| BR-10 | Aktif→Selesai dan pembayaran atomik | repo._connect/create_entry/finish_transaction | diperbaiki | AT-08; rollback dan konkurensi |
| BR-11 | Biaya berubah perlu konfirmasi ulang | PriceChangedError; complete_payment; payment_page.py | diperbaiki | AT-09; total dan kembalian UI |
| BR-12 | Selesai immutable; pendapatan total_biaya | schema.sql immutable triggers; revenue_summary | diperbaiki | AT-08/10/12 |
| NFR-01 | Indonesia, rupiah, status ikon/teks | ui/common.py dan seluruh halaman; pesan service | diperbaiki | smoke kontrol; cek visual manual tersisa |
| NFR-02 | 19/20 <=3 detik, 1.000 transaksi | scripts/benchmark_nfr02.py | sudah | 20/20 tiap operasi; service/repository Linux |
| NFR-03 | Hash salt, otorisasi, query parameter | logic/security.py; SecuredService; sqlite_repository.py | diperbaiki | AT-02/12; tes hash dan sesi |
| NFR-04 | Atomic, anti duplikasi dan melebihi kapasitas | schema.sql; repo._connect/create_entry/finish_transaction | diperbaiki | AT-08; injeksi kegagalan/konkurensi |
| NFR-05 | Persistensi setelah restart | config.py; bootstrap.py; SQLite file data/qpark.db | sudah | test_configuration: buka ulang file |
| NFR-06 | 1366×768 tanpa tumpang tindih | ResponsiveRow/scroll; NavigationRail.expand; ui/*.py | diperbaiki | kontrol/serializer lulus; render Windows belum diverifikasi |
| NFR-07 | Pemisahan UI/logika/data dan panduan | app/bootstrap.py; config.py; repository.py; README.md; docs | diperbaiki | audit impor/struktur; konfigurasi teruji |

## Komponen yang ditambah

| Komponen | File/fungsi | Status |
|---|---|---|
| Sesi yang bisa dicabut | logic/sessions.py; AuthService.logout | ditambah |
| Pemilihan backend | config.py; bootstrap.create_repository; .env.example | ditambah |
| Detail riwayat dengan otorisasi ulang | ParkingService.transaction_detail | ditambah |
| Error backend yang aman | domain/errors.py: DataAccessError | ditambah |
| Immutability pada database | schema.sql: tiga trigger immutable | ditambah |
| Pengujian tambahan | tests/test_acceptance.py, test_launcher.py, test_configuration.py, test_ui_smoke.py | ditambah |
| Rencana migrasi dan checklist | docs/SUPABASE_MIGRASI.md; UJI_MANUAL.md | ditambah |

## Pemetaan use case

| Use case | Implementasi | Verifikasi |
|---|---|---|
| UC-01 | AuthService.login; login_page | AT-01; smoke login |
| UC-02 | ParkingService.dashboard; dashboard_page | AT-03/05; error tidak menjadi slot kosong |
| UC-03 | ParkingService.record_entry; entry_page | AT-03/04/05/08 |
| UC-04 | quote_payment/complete_payment; payment_page | AT-06/07/08/09 |
| UC-05 | history/transaction_detail; AdminService.revenue | AT-10 dan role guard |
| UC-06 | AdminService.update_settings; settings_page | AT-11 dan dirty form |
| UC-07 | create_officer/set_officer_active | AT-02/12 |
| UC-08 | AuthService.logout; ParkingApp.confirm_leave | tes logout service dan batal/lanjut UI |

## Pemetaan acceptance test

| AT | Test otomatis utama | Uji Windows |
|---|---|---|
| AT-01 | test_login_valid_invalid_and_role_guard; test_at01_*; tes UI logout | Belum |
| AT-02 | test_at02_* | Belum |
| AT-03 | test_at03_entry_snapshot_timestamp_officer_and_slots | Belum |
| AT-04 | test_plate_normalization_duplicate_and_capacity; test_at04_* | Belum |
| AT-05 | test_at05_*; test_plate_validation | Belum |
| AT-06 | test_billing_boundaries_and_across_midnight; test_at06_* | Belum |
| AT-07 | test_payment_and_repeat_prevention; test_at07_* | Belum |
| AT-08 | test_at08_*; test_payment_cancel_then_pay_and_double_click | Belum |
| AT-09 | test_price_change_requires_reconfirmation; test_at09_*; tes UI harga baru | Belum |
| AT-10 | test_at10_* | Belum |
| AT-11 | test_rate_snapshot_capacity_validation_and_history; test_at11_* | Belum |
| AT-12 | test_at12_*; test_configuration; benchmark; kontrol UI | Sebagian otomatis; render/perangkat belum |
