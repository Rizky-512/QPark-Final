# Aset web

Renderer Flutter disertakan oleh build --no-web-resources-cdn. Font Roboto-Regular.ttf diwarisi dari build QPark v2, didaftarkan eksplisit sebagai font lokal agar teks tidak menunggu font dari internet. Ikon dan warna merek tetap dari proyek awal. `lib/ui/common.dart` tidak berubah.

ZXing JS 0.23.0 disertakan pada web/vendor untuk pemindai web, sumber https://unpkg.com/@zxing/library@0.23.0/umd/index.min.js dan lisensi pada LISENSI_PIHAK_KETIGA/zxing-0.23.0.txt. mobile_scanner menggunakan adaptor native pada Android/iOS. Lisensi paket Flutter tersedia dalam assets/NOTICES hasil build.

Worker Drift dan sqlite3.wasm bawaan v2 tetap ada sebagai aset warisan; runtime v3 memakai API pusat dan tidak membuka database transaksi SQLite browser.

Gambar samples/kendaraan_uji.png merupakan ilustrasi uji dengan nopol contoh, bukan gambar kamera lapangan.
