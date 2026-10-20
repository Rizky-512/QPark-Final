# Keterlacakan SRS → implementasi → bukti uji

Sumber: PRD/SRS terbaru yang disertakan. Terimplementasi tidak otomatis berarti uji lapangan sudah lulus. Nama file tanpa folder UI berada di `lib/ui/pages/`; remote_service berada di `lib/logic/`.

## Functional requirements

| FR | Use case | Acceptance test | Implementasi | Status |
|---|---|---|---|---|
| FR-01 | UC-01 | AT-01 | lib/ui/app.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-02 | UC-01 | AT-01, AT-02 | lib/logic/remote_service.dart; driver_page.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-03 | UC-01 UC-08 | AT-01, AT-02 | server/rules.py; lib/domain/rules.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-04 | UC-02 UC-11 | AT-08, AT-28 | server/store.py; remote_common.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-05 | UC-03 | AT-03 | server/store.py; driver_page.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-06 | UC-03 | AT-03 | server/store.py; remote_common.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-07 | UC-07 | AT-04 | server/store.py; login_page.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-08 | UC-12 | AT-05, AT-39 | remote_service.dart; server/store.py | Terimplementasi; bukti tes otomatis tersedia. |
| FR-09 | UC-08 | AT-06, AT-07 | entry_page.dart | Terimplementasi; input uji/pemindai tersedia; perangkat kamera lapangan belum diverifikasi. |
| FR-10 | UC-08 | AT-06, AT-08, AT-09, AT-10 | server/store.py; schema.sql | Terimplementasi; bukti tes otomatis tersedia. |
| FR-11 | UC-08 | AT-07, AT-08, AT-09, AT-10 | server/store.py; entry_page.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-12 | UC-02 UC-11 | AT-08, AT-23, AT-28 | server/store.py; schema.sql | Terimplementasi; bukti tes otomatis tersedia. |
| FR-13 | UC-02 UC-03 UC-06 UC-11 | AT-29, AT-38 | remote_service.dart | Terimplementasi; HTTP/klien diuji, benchmark 100 perubahan UI dan dua jaringan belum dijalankan. |
| FR-14 | UC-11 | AT-28 | dashboard_page.dart; server/store.py | Terimplementasi; bukti tes otomatis tersedia. |
| FR-15 | UC-02 UC-03 UC-05 UC-08 UC-09 UC-10 | AT-30 | remote_service.dart; app.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-16 | UC-04 | AT-11, AT-12, AT-32 | server/rules.py; payment_page.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-17 | UC-04 | AT-12, AT-13, AT-14 | server/store.py; schema.sql | Terimplementasi; bukti tes otomatis tersedia. |
| FR-18 | UC-05 | AT-13, AT-15 | payment_page.dart; server/store.py | Terimplementasi; bukti tes otomatis tersedia. |
| FR-19 | UC-05 | AT-15, AT-32 | server/store.py; schema.sql | Terimplementasi; bukti tes otomatis tersedia. |
| FR-20 | UC-05 | AT-16 | server/store.py; remote_service.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-21 | UC-04 UC-06 UC-09 | AT-17, AT-18 | server/store.py; schema.sql | Terimplementasi; bukti tes otomatis tersedia. |
| FR-22 | UC-05 UC-06 | AT-18 | server/store.py; payment_page.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-23 | UC-06 | AT-19 | payment_page.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-24 | UC-06 UC-09 | AT-20 | server/store.py | Terimplementasi; bukti tes otomatis tersedia. |
| FR-25 | UC-09 | AT-21 | exit_page.dart; mobile_scanner | Terimplementasi; input uji/pemindai tersedia; perangkat kamera lapangan belum diverifikasi. |
| FR-26 | UC-09 | AT-22, AT-23, AT-26, AT-32, AT-40 | server/store.py; exit_page.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-27 | UC-10 | AT-24, AT-40 | server/store.py; exit_page.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-28 | UC-09 UC-10 | AT-25, AT-40 | server/store.py; exit_page.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-29 | UC-09 | AT-20, AT-21, AT-22, AT-27 | server/store.py; exit_page.dart | Terimplementasi; bukti tes otomatis tersedia. |
| FR-30 | UC-05 UC-07 UC-08 UC-09 UC-10 UC-12 | AT-31 | server/store.py; schema.sql | Terimplementasi; bukti tes otomatis tersedia. |

## Non-functional requirements

| NFR | Status dan batas bukti |
|---|---|
| NFR-01 | Polling 2 detik tersedia. Belum menyatakan lulus profil 100 perubahan UI / 10 klien. |
| NFR-02 | Profil HTTP 20 sesi / 10 klien / 100 mutasi diuji; lihat angka aktual server-tests.txt. |
| NFR-03 | Lulus tes kapasitas terakhir 100 pasangan dan pembayaran 100 permintaan bersamaan; indeks unik dan transaksi diuji. |
| NFR-04 | Otorisasi endpoint, password bersalt, revoke/8 jam diuji; sertifikat HTTPS tersedia sebagai konfigurasi, belum diuji dua jaringan. |
| NFR-05 | Restart repository dan backup/restore SQLite diuji; data dan token tetap konsisten. |
| NFR-06 | Belum diuji pada peserta pengguna. |
| NFR-07 | Widget 360×800 dan 1280×720 diuji tanpa overflow; uji QR pada perangkat fisik belum dilakukan. |
| NFR-08 | Aturan server/rules.py terpisah, clock terinjeksi pada tes tanpa kontrol pada UI. |
| NFR-09 | Gambar dipakai di memori; tidak diunggah. Tidak mengumpulkan KTP/GPS/rekening. |
| NFR-10 | Tes respons hilang/kunci tetap, retry, indikator offline, dan revokasi offline tersedia; lihat hasil aktual. |

## Use case

| UC | Modul | Status |
|---|---|---|
| UC-01 | driver_page + remote_service | Terimplementasi; lihat AT terkait. |
| UC-02 | CapacityCard + capacity API | Terimplementasi; lihat AT terkait. |
| UC-03 | driver_page + ticket API | Terimplementasi; lihat AT terkait. |
| UC-04 | payment_page + invoice API | Terimplementasi; lihat AT terkait. |
| UC-05 | payment_page + payment API | Terimplementasi; lihat AT terkait. |
| UC-06 | payment_page + windows | Terimplementasi; lihat AT terkait. |
| UC-07 | login_page + login API | Terimplementasi; lihat AT terkait. |
| UC-08 | entry_page + entry API | Terimplementasi; lihat AT terkait. |
| UC-09 | exit_page + scan/authorize | Terimplementasi; lihat AT terkait. |
| UC-10 | exit_page + complete | Terimplementasi; lihat AT terkait. |
| UC-11 | dashboard_page + monitor | Terimplementasi; lihat AT terkait. |
| UC-12 | app + remote_service + logout API | Terimplementasi; lihat AT terkait. |

## Acceptance test

| AT | Bukti / tingkat verifikasi |
|---|---|
| AT-01 | Tes Flutter CRUD/persistensi dan widget; penghapusan tidak memanggil mutasi sesi. |
| AT-02 | Tes normalisasi/duplikasi lokal + rules server. |
| AT-03 | Tes ticket API dan tiga konteks browser independen; nopol sama menerima tiket yang sama. |
| AT-04 | Tes login benar/salah dan endpoint tanpa autentikasi. |
| AT-05 | Tes logout server menolak token lama + widget kembali mode pengendara. |
| AT-06 | Tes server dan alur browser: memilih gambar uji, mengetik nopol, mencentang verifikasi, lalu masuk. |
| AT-07 | Tes penolakan verifikasi/gambar tidak terbaca; UI menonaktifkan simpan tanpa foto. |
| AT-08 | Tes 20 diterima / ke-21 ditolak. |
| AT-09 | 100 pasangan permintaan bersamaan; tepat satu menerima tempat terakhir. |
| AT-10 | Tes sesi aktif ganda dan retry identik. |
| AT-11 | Tes durasi sesuai semua contoh termasuk negatif. |
| AT-12 | Tes snapshot melintasi pergantian jam. |
| AT-13 | Tes tepat batas 5 menit ditolak. |
| AT-14 | 10 permintaan tagihan bersamaan mendapat invoice sama. |
| AT-15 | Tes pending, gagal, sukses dan waktu jendela. |
| AT-16 | 100 permintaan bayar paralel dan retry; satu pelunasan/jendela. |
| AT-17 | Tes refresh/polling tidak menggandakan penalti. |
| AT-18 | Tes jendela baru dan penalti berikutnya setelah kedaluwarsa. |
| AT-19 | Tes token/status sebelum lunas, setelah lunas, kedaluwarsa, selesai; UI QR berbeda. |
| AT-20 | Tes token jendela lama ditolak setelah penalti dibayar. |
| AT-21 | Tes verifikasi wajib dan nopol berbeda ditolak. |
| AT-22 | Tes deadline −1 detik, tepat batas, +1 detik. |
| AT-23 | Tes EXIT_AUTHORIZED tetap memakai kapasitas. |
| AT-24 | Tes selesai sekali dan konfirmasi berulang. |
| AT-25 | Tes batal dan tepat 120 detik habis, kapasitas tidak berubah. |
| AT-26 | 10 permintaan izin paralel menghasilkan satu persetujuan. |
| AT-27 | Tes QR pembayaran/token sembarang/selesai/kedaluwarsa ditolak. |
| AT-28 | Tes monitor hanya untuk petugas dan UI pencarian. |
| AT-29 | Tiga konteks browser tersinkron pada masuk, lunas, dan selesai; profil 100 perubahan UI belum dinyatakan lulus. |
| AT-30 | Tes Flutter respons hilang/kunci tetap, retry HTTP setelah commit, serta indikator offline pada browser. |
| AT-31 | Inspeksi audit otomatis tidak mengandung password/token mentah. |
| AT-32 | Tes jam server dan Stopwatch tampilan; API tidak menerima waktu/nilai dari klien. |
| AT-33 | Bagian respons HTTP diukur; 100 perubahan UI antarperangkat belum diukur. |
| AT-34 | Tes backup, restart, restore dan konsistensi token. |
| AT-35 | Belum dijalankan: memerlukan peserta uji. |
| AT-36 | Widget dua viewport lulus; pemindaian QR pada perangkat fisik belum diuji. |
| AT-37 | Inspeksi modul dan kode; gambar tidak diunggah, tidak ada UI jam uji. |
| AT-38 | Belum dijalankan: memerlukan dua jaringan dan HTTPS yang dapat dijangkau. |
| AT-39 | Tes logout offline → terkunci → revoke setelah online; maksimum 8 jam server. |
| AT-40 | Tes izinkan tepat deadline, keluar 119 detik kemudian tanpa penalti. |
