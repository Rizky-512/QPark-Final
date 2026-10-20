# Perubahan dari Python/Flet ke Flutter

- Seluruh UI ditulis ulang dengan Flutter Material 3, warna hijau terpusat, sidebar web dan navigasi bawah HP.
- Logika Python dipindah ke Dart: normalisasi pelat, biaya/waktu, tunai, snapshot tarif, validasi, otorisasi dan sesi.
- Kontrak ParkingRepository tetap terpisah; SQLite melalui Drift mendukung native dan browser. Skema dan trigger SRS dipertahankan dengan timestamp epoch milidetik.
- Bootstrap memilih backend lokal dan membuat demo sekali. Supabase hanya rencana, tidak ada secret/SDK Supabase.
- Proyek Android/iOS/web standar, pubspec.lock, konfigurasi VS Code, launcher .bat, serta hasil web rilis ditambahkan.
- 51 tes Flutter menggantikan verifikasi khusus platform baru; proyek Python sebelumnya tetap terpisah.
- Dokumentasi traceability 20 FR, 12 BR, 7 NFR; seluruh UC dan checklist AT diperbarui.

File utama: lib/main.dart, bootstrap.dart, config.dart; lib/domain/*.dart; lib/logic/*.dart; lib/data/*.dart; lib/ui/app.dart, common.dart, pages/*.dart; assets/schema.sql; pubspec.yaml/lock; test/*.dart; integration_test/app_test.dart; scripts/serve_web.py; buka_web.bat; jalankan_web.bat; jalankan_android.bat; .env.example; .vscode/launch.json; README.md; docs/*.md.
