# Daftar perubahan QPark 3

Asal: QPark-Flutter-Final.zip versi terakhir. Proyek platform, tema dan komponen visual dipertahankan. Source baru tidak dibuat melalui flutter create.

- Tambah mode pengendara, nopol lokal, tiket lintas perangkat, QR, simulator pembayaran, dan alur keluar.
- Revisi tarif/jendela waktu, verifikasi masuk, monitor, login/logout, launcher serta dokumentasi.
- Tambah server pusat, transaksi/idempotensi, audit dan pengujian baru.
- Menu admin, motor dan kas tunai dinonaktifkan. Source/tes lama diarsipkan, bukan dipakai untuk menyatakan kelulusan SRS baru.

| Berkas | Perubahan |
|---|---|
| .env.example | Diubah |
| .vscode/launch.json | Diubah |
| README.md | Diubah |
| analysis_options.yaml | Diubah |
| android/app/src/debug/AndroidManifest.xml | Diubah |
| android/app/src/main/AndroidManifest.xml | Diubah |
| assets/fonts/Roboto-Regular.ttf | Ditambahkan |
| buka_web.bat | Diubah |
| docs/ARSITEKTUR_DAN_ASUMSI.md | Diubah |
| docs/ASET_WEB.md | Diubah |
| docs/LISENSI_PIHAK_KETIGA/zxing-0.23.0.txt | Ditambahkan |
| docs/PRD_SRS_Prototipe_Aplikasi_Parkir.docx | Ditambahkan |
| docs/TRACEABILITY_SRS.md | Diubah |
| docs/UJI_MANUAL.md | Diubah |
| docs/hasil/flutter-analyze-v3.txt | Ditambahkan |
| docs/hasil/flutter-build-web-v3.txt | Ditambahkan |
| docs/hasil/flutter-doctor-v3.txt | Ditambahkan |
| docs/hasil/flutter-test-v3.txt | Ditambahkan |
| docs/hasil/server-tests.txt | Ditambahkan |
| integration_test/app_test.dart | Diubah |
| ios/Runner/GeneratedPluginRegistrant.m | Diubah |
| ios/Runner/Info.plist | Diubah |
| jalankan_android.bat | Diubah |
| jalankan_web.bat | Diubah |
| lib/bootstrap.dart | Diubah |
| lib/config.dart | Diubah |
| lib/data/remote_repository.dart | Ditambahkan |
| lib/domain/rules.dart | Diubah |
| lib/logic/remote_service.dart | Ditambahkan |
| lib/main.dart | Diubah |
| lib/ui/app.dart | Diubah |
| lib/ui/pages/dashboard_page.dart | Diubah |
| lib/ui/pages/driver_page.dart | Ditambahkan |
| lib/ui/pages/entry_page.dart | Diubah |
| lib/ui/pages/exit_page.dart | Ditambahkan |
| lib/ui/pages/login_page.dart | Diubah |
| lib/ui/pages/payment_page.dart | Diubah |
| lib/ui/remote_common.dart | Ditambahkan |
| mulai.sh | Ditambahkan |
| pubspec.lock | Diubah |
| pubspec.yaml | Diubah |
| samples/kendaraan_uji.png | Ditambahkan |
| scripts/backup_database.py | Ditambahkan |
| scripts/build_release.py | Ditambahkan |
| scripts/import_legacy.py | Ditambahkan |
| scripts/launch.py | Ditambahkan |
| scripts/serve_web.py | Diubah |
| server/__init__.py | Ditambahkan |
| server/app.py | Ditambahkan |
| server/rules.py | Ditambahkan |
| server/schema.sql | Ditambahkan |
| server/store.py | Ditambahkan |
| server/tests/test_http.py | Ditambahkan |
| server/tests/test_store.py | Ditambahkan |
| test/remote_service_test.dart | Ditambahkan |
| test/widget_test.dart | Diubah |
| web/index.html | Diubah |
| web/manifest.json | Diubah |
| web/vendor/zxing-0.23.0.min.js | Ditambahkan |
| docs/HASIL_PENGUJIAN.md | Hasil v3 dan batas validasi diperbarui |
| docs/hasil/launcher-v3.json | Bukti launcher folder dengan spasi |
| rilis/web + rilis/source_manifest.json | Build web v3 terbaru dan pemeriksaan kesesuaian source |
| scripts/browser_smoke.cjs | Skenario browser tiga klien; opsional untuk developer |
| docs/hasil/browser-flow-v3.json | Bukti alur browser aktual |
