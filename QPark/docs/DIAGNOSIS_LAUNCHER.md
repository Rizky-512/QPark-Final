# Diagnosis dan pemulihan launcher

Tidak ada traceback Windows pada masukan pengguna; gejala kerja yang dicatat adalah **jendela tidak muncul / langsung tertutup**. Karena itu tidak ada klaim bahwa versi Python, Microsoft Store, antivirus, atau venv rusak tertentu telah terbukti menjadi penyebab pada laptop pengguna.

## Temuan dari kode awal dan pemeriksaan Flet 1.0.2

| Area | Temuan yang terverifikasi | Perbaikan |
|---|---|---|
| Kesehatan venv | `_ensure_venv` langsung memakai executable bila file ada; pip/interpreter tidak diuji | Probe Python, SQLite, SSL, pip; ensurepip; bangun lingkungan baru jika rusak |
| Flet | `_flet_ready` hanya membaca metadata dan menerima semua mayor >=1 | Import `flet` dan `flet_desktop`, periksa API dan versi tepat 1.0.2 |
| Dependensi | `flet[all]>=1.0,<2` memasang CLI/web yang tidak diperlukan; rentang itu juga menerima 1.1+ | `flet[desktop]==1.0.2`, tanpa upgrade pip setiap peluncuran |
| API async | `window.center`, `window.to_front`, dan `TextField.focus` merupakan coroutine pada paket 1.0.2 yang diinstal; kode lama tidak await | Entry point dan callback terkait menggunakan async/await |
| Navigasi | Rail lama memakai extended=True sekaligus label_type=ALL; ruang vertikal di Column tidak dialokasikan dengan expand | label_type=NONE, expand=True, scrollable=True |
| Lokasi file | ROOT dan cwd lama pada launcher sudah benar; bukan temuan penyebab yang terbukti | Tetap absolut; bersihkan PYTHONHOME dan tetapkan PYTHONPATH proyek untuk proses anak |
| Error | Launcher lama tidak pause ketika dijalankan langsung dan hanya mengembalikan kode anak | Pause pada kegagalan di Windows, exit code dipertahankan, startup marker membedakan sesi siap dari client berhenti dini |

`ft.run(main)` valid untuk Flet 1.0.2; tidak perlu mengganti menjadi `flet run`. Paket desktop masih dapat mengunduh binary client secara terpisah. Tidak ada bukti di lampiran bahwa unduhan tersebut gagal pada perangkat pengguna.

## Alur pemulihan

1. Pakai lingkungan pemulihan `.venv-qpark` bila sudah sehat, atau periksa `.venv`.
2. Uji executable dan pip, bukan keberadaan file saja. Jika pip rusak, coba `ensurepip`.
3. Jika perlu, karantina `.venv` menjadi `.venv-rusak-<waktu>`, lalu buat ulang lewat Python dasar yang sehat. Data parkir tidak dihapus.
4. Bila executable `.venv` masih dipakai VS Code, buat `.venv-qpark` dengan interpreter dasar.
5. Pasang requirements hanya jika probe impor/versi gagal. Lakukan force-reinstall sekali jika metadata terpasang tetapi impor tetap gagal.
6. Bila penyiapan gagal, boleh gunakan interpreter lain yang sudah memiliki dependensi yang tepat. Launcher tidak diam-diam memasang paket ke Python global.
7. Jalankan `main.py`, teruskan stdout/stderr dan exit code. Bila kode 0 tetapi callback halaman belum siap, laporkan kegagalan startup.

`--check` hanya menyiapkan dan memeriksa dependensi, tanpa membuka UI. `--no-pause` digunakan oleh run.bat agar tidak pause dua kali.

## Bukti dan batas

- Dua belas unit test launcher menguji impor rusak, pip hilang, rebuild, venv yang terkunci, tidak reinstall saat sehat, timeout, exit code anak, dan startup marker.
- Penyiapan venv/dependensi serta pemanggilan `--check` diuji nyata di Linux/Python 3.12.14. Pemanggilan berikutnya menampilkan “Dependensi desktop siap” tanpa instalasi ulang.
- `python main.py` dicoba pada Linux tanpa display; Flet mendeteksi lingkungan server dan memulai server lokal, lalu proses dihentikan setelah 30 detik. Ini **bukan kelulusan pembukaan jendela desktop**.
- Tidak ada renderer native Windows di lingkungan pengujian. Unduhan alat render tambahan juga tidak berhasil; tidak ada screenshot aplikasi yang diklaim telah diverifikasi.
- `run.bat`, perilaku pause/py launcher, posisi/fokus jendela, DPI, firewall, dan cache client di Windows masih memerlukan checklist manual.

Referensi API resmi: [instalasi Flet](https://flet.dev/docs/getting-started/installation/) dan [menjalankan aplikasi Flet](https://flet.dev/docs/getting-started/running-app/). Tanda tangan coroutine juga diperiksa langsung dari paket Flet 1.0.2 yang terpasang.
