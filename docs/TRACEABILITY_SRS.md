# Traceability SRS v1.0 → Flutter

Acuan: SRS v1.0 dari lampiran dan proyek Python revisi. Lingkup bisnis dipertahankan; target desktop diganti HP/web atas permintaan pengguna. Laporan hasil uji historis tersedia dalam riwayat Git; jalankan ulang tes untuk memeriksa versi aktif.

Implementasi aktif memakai arsitektur klien–server: UI Flutter (`lib/ui`) → `lib/logic/remote_service.dart` → kontrak `/api/*` yang dijalankan oleh backend lokal (`server/`, Python + SQLite) atau Supabase (`supabase/migrations`, RPC `qpark_request`). Lapisan SQLite lokal versi awal (Drift, `QParkService`, `ParkingRepository`) telah dihapus; implementasi lamanya tetap dapat dilihat pada riwayat Git (commit `d983183` dan sebelumnya).

Kolom backend menyebut modul Python; perilaku yang sama tersedia di fungsi PostgreSQL Supabase. Status **disesuaikan** berarti aturan aktif mengikuti keputusan produk terbaru pada README.

| Kode | Kebutuhan | Implementasi aktif | Status |
|---|---|---|---|
| FR-01 | Login aktif dan pesan umum | `POST /api/login` (server/store.py); ui/pages/login_page.dart | ditambah |
| FR-02 | Logout dan penutupan sesi | `POST /api/logout`; logic/remote_service.dart: logout; ui/app.dart | ditambah |
| FR-03 | Tambah/aktif/nonaktif petugas | `/api/admin/users` (server/management.py); ui/pages/admin_page.dart | ditambah |
| FR-04 | Peran dan akun nonaktif pada sesi | server/store.py: `_officer`; perubahan akun mencabut sesi | ditambah |
| FR-05 | Kartu kapasitas/terisi/kosong/status | `GET /api/capacity` (server/vehicle_categories.py); ui/pages/dashboard_page.dart, ui/app.dart | ditambah |
| FR-06 | Muat ulang slot setelah perubahan | logic/remote_service.dart: polling adaptif dan sync setelah mutasi | ditambah |
| FR-07 | Daftar aktif dan cari pelat/ID | `GET /api/officer/monitor`; ui/pages/dashboard_page.dart | ditambah |
| FR-08 | Validasi form masuk | domain/rules.dart: normalizePlate; server/rules.py: plate; ui/pages/entry_page.dart | ditambah |
| FR-09 | ID/waktu/tarif/status/petugas saat masuk | `POST /api/officer/entry` (server/store.py) | ditambah |
| FR-10 | Hasil masuk dan kegagalan jelas | ui/pages/entry_page.dart; domain/errors.dart; data/remote_repository.dart: ApiError | ditambah |
| FR-11 | Pilih transaksi dan estimasi lengkap | `POST /api/invoice`, `/api/officer/manual-quote`; ui/pages/payment_page.dart, manual_payment_page.dart | ditambah |
| FR-12 | Pembulatan jam dan lintas hari | server/rules.py: charge; domain/parking_cost.dart | disesuaikan |
| FR-13 | Tunai dan kembalian sebelum konfirmasi | ui/pages/manual_payment_page.dart | ditambah |
| FR-14 | Konfirmasi dan simpan pembayaran atomik | `POST /api/payment`, `/api/officer/manual-pay` (server/management.py: settle) | ditambah |
| FR-15 | Anti klik ganda, batal, rollback | operation_key idempoten (logic/remote_service.dart: post; server/store.py: `_operation`) | ditambah |
| FR-16 | Bukti pembayaran lengkap | domain/parking_receipt.dart; ui/widgets/receipt_button.dart | ditambah |
| FR-17 | Filter riwayat inklusif dan detail | `/api/officer/history`, `/api/history` (server/management.py: history); ui/pages/remote_history_page.dart | ditambah |
| FR-18 | Agregasi pendapatan khusus Admin | server/management.py: history (total); `/api/admin/analytics`; ui/pages/analytics_page.dart | ditambah |
| FR-19 | Ubah kapasitas valid | `/api/admin/settings`; ui/pages/admin_page.dart | ditambah |
| FR-20 | Ubah tarif bulat positif; snapshot tetap | `/api/admin/settings`; tarif disalin saat `POST /api/officer/entry` | ditambah |
| BR-01 | Konfigurasi Motor/Mobil; integer valid | server/management.py: settings; server/vehicle_categories.py | ditambah |
| BR-02 | Slot dihitung dari transaksi aktif | server/vehicle_categories.py: capacity_view | ditambah |
| BR-03 | Penuh ditolak; kapasitas >= aktif | server/store.py: enter; server/management.py: validasi settings | ditambah |
| BR-04 | Pelat kapital tanpa spasi, alnum | domain/rules.dart: normalizePlate; server/rules.py: plate (1–32 karakter) | disesuaikan |
| BR-05 | Satu pelat aktif lintas jenis | server/schema.sql: indeks unik `active_plate` | ditambah |
| BR-06 | Waktu otomatis; tidak mundur | Waktu server (server/store.py); server/rules.py: charge menolak durasi negatif | ditambah |
| BR-07 | Pembulatan per jam, minimum satu jam | server/rules.py: charge (jam penuh dibulatkan ke bawah, minimum satu jam) | disesuaikan |
| BR-08 | Tarif disalin saat masuk | server/store.py: enter (hourly_rate sesi) | ditambah |
| BR-09 | Tunai integer cukup, kembalian benar | server/management.py: pay_manual; ui/pages/manual_payment_page.dart | ditambah |
| BR-10 | Aktif→Selesai dan pembayaran atomik | Transaksi SQLite/PostgreSQL per permintaan (server/store.py: dispatch) | ditambah |
| BR-11 | Biaya berubah perlu konfirmasi ulang | Snapshot tagihan 5 menit (server/rules.py: QUOTE_SECONDS); tagihan lama ditolak | ditambah |
| BR-12 | Selesai immutable; pendapatan total_biaya | Status sesi `COMPLETED` dan tabel audit (server/schema.sql) | ditambah |
| NFR-01 | Indonesia, rupiah, status ikon/teks | ui/common.dart, ui/pages/*; locale id_ID | ditambah |
| NFR-02 | Respons <=3 detik | server/tests/test_http.py: profil 10 klien, 100 mutasi, p95 | ditambah |
| NFR-03 | Hash salt, otorisasi, query parameter | server/store.py: password_hash (PBKDF2), `_officer`; query berparameter | ditambah |
| NFR-04 | Atomic, anti duplikasi dan melebihi kapasitas | server/tests/test_store.py, test_vehicle_capacity.py (konkurensi slot terakhir) | ditambah |
| NFR-05 | Persistensi setelah restart | Database server (data/qpark_server_v3.db atau Supabase); server/recovery.py | ditambah |
| NFR-06 | 1366×768 tanpa tumpang tindih | ui/app.dart: LayoutBuilder; test/widget_test.dart | ditambah |
| NFR-07 | Pemisahan UI/logika/data dan panduan | lib/domain, logic, data, ui; bootstrap.dart; README.md | ditambah |

## Use case

| UC | Halaman / endpoint |
|---|---|
| UC-01 | login_page / `POST /api/login` |
| UC-02 | dashboard_page / `GET /api/capacity`, `GET /api/officer/monitor` |
| UC-03 | entry_page / `POST /api/officer/entry` |
| UC-04 | payment_page, manual_payment_page, exit_page / invoice, payment, scan, authorize, complete |
| UC-05 | remote_history_page, analytics_page / history, analytics |
| UC-06 | admin_page / `/api/admin/settings` |
| UC-07 | admin_page / `/api/admin/users` |
| UC-08 | ui/app.dart / logout |
