# Hasil pengujian QPark final

Pengujian otomatis terakhir sebelum pengemasan: **58 lulus, 0 gagal, 0 error, 0 dilewati**. Delapan tes asli di `tests/test_parking.py` dipertahankan tanpa perubahan. Gate terakhir sebelum ZIP: 58 tes dalam 9,896 detik, seluruhnya OK.

## Lingkungan uji

- Python 3.12.14; Flet 1.0.2 dan flet-desktop 1.0.2 dari requirements proyek.
- Linux 6.18.44 x86_64, glibc 2.39; CPU Intel Xeon Platinum 8370C 2.80 GHz.
- 9 CPU terlihat oleh proses; batas memori container 8 GiB.
- SQLite file pada direktori sementara; tidak ada perubahan ke data pengguna.
- Tidak tersedia sesi desktop Windows. Tidak ada klaim lulus render native Windows.

## Unit test dan smoke test

Perintah: `python -m unittest discover -v`, dengan interpreter venv yang telah memasang requirements.

| File | Jumlah | Cakupan |
|---|---:|---|
| tests/test_parking.py | 8 | Tes asli: login/peran, pelat, kapasitas, biaya, pembayaran, perubahan harga, tarif/riwayat, konsistensi skema |
| tests/test_acceptance.py | 27 | AT-01–12 tambahan; batas waktu, integer rupiah, filter inklusif, rollback nyata, konkurensi, immutability, sesi nonaktif |
| tests/test_launcher.py | 12 | Kesehatan venv/pip/impor, rebuild, venv terkunci, exit code, marker startup, tidak reinstall saat siap |
| tests/test_configuration.py | 3 | Konfigurasi, backend tidak didukung, bootstrap/reopen tidak mengubah transaksi/tarif/status akun |
| tests/test_ui_smoke.py | 8 | Konstruksi dan serialisasi enam halaman; callback form, logout, database error, bayar/batal/klik ganda, harga baru, menu/peran, await window |
| **Total** | **58** | **Semua lulus** |

Smoke test menggunakan **kontrol dan serializer Flet 1.0.2 yang asli**, dengan FakePage sebagai pengganti koneksi desktop. Callback simpan masuk, konfirmasi pembayaran, pembatalan, konfirmasi ulang, logout, dan pengaturan dijalankan. Uji ini tidak memeriksa pixel, rendering Flutter, atau traversal keyboard native.

Rollback diuji dengan injeksi `sqlite3.OperationalError` saat pembacaan hasil setelah INSERT/UPDATE, sebelum commit. Database harus tetap sama seperti sebelum operasi. Konkurensi dua thread menguji kapasitas satu slot dan pembayaran satu transaksi; tepat satu operasi boleh sukses.

## Benchmark NFR-02

Perintah: `python scripts/benchmark_nfr02.py`. Database berisi 1.000 transaksi selesai; 20 percobaan per operasi. Simpan mengukur alur service masuk, quote, dan konfirmasi bayar. Ambang penerimaan adalah sedikitnya 19/20 percobaan <=3 detik.

| Operasi | Lulus | Median | P95 | Maksimum |
|---|---:|---:|---:|---:|
| Dashboard | 20/20 | 0,0008 dtk | 0,0011 dtk | 0,0012 dtk |
| Pencarian | 20/20 | 0,0009 dtk | 0,0012 dtk | 0,0012 dtk |
| Simpan masuk dan bayar | 20/20 | 0,0023 dtk | 0,0034 dtk | 0,0035 dtk |

Ini waktu service/repository, bukan waktu render penuh di laptop Windows. Jalankan ulang benchmark dan periksa waktu UI pada perangkat tim sebelum penerimaan NFR-02 akhir.

## Pemeriksaan tambahan

- Semua berkas Python diparse memakai grammar Python 3.10; tidak ditemukan sintaks yang membutuhkan 3.11–3.14.
- Semua berkas Python dikompilasi; tidak ada error sintaks.
- Tidak ada impor adapter SQLite dari lapisan UI/logika/domain; bootstrap yang memilih adapter.
- SHA-256 tests/test_parking.py asli dan final sama: `586db9edb9feaf9feb457774fc68577be0202fd528d7529cde339072ee92cbd1`.
- `python launcher.py --check --no-pause` diuji pada lingkungan lokal; lingkungan sehat tidak memasang dependensi ulang.
- `python main.py` dicoba pada Linux tanpa display. Flet memilih server web otomatis dan proses dihentikan setelah 30 detik. Hal ini tidak membuktikan jendela native Windows sudah terbuka.

## Belum terverifikasi secara langsung

`run.bat` dan Windows Python Launcher, unduhan client desktop Windows, penempatan/fokus jendela, layout 1366×768, skala DPI, Tab/Enter native, firewall/antivirus, dan perangkat pengguna. Upaya menyediakan alat render di lingkungan ini tidak berhasil, sehingga tidak ada screenshot visual final yang dijadikan bukti.

Gunakan `UJI_MANUAL.md` untuk AT-01–AT-12 di Windows. Status implementasi SRS terdapat di `TRACEABILITY_SRS.md`; NFR-06 belum dinyatakan lulus secara visual.
