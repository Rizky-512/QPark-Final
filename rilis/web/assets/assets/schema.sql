PRAGMA foreign_keys = ON;

-- @statement

CREATE TABLE IF NOT EXISTS users (
    id_user INTEGER PRIMARY KEY AUTOINCREMENT,
    nama TEXT NOT NULL CHECK (length(trim(nama)) > 0),
    username TEXT NOT NULL UNIQUE CHECK (username = lower(username)),
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('Admin', 'Petugas')),
    aktif INTEGER NOT NULL DEFAULT 1 CHECK (aktif IN (0, 1))
);

-- @statement

CREATE TABLE IF NOT EXISTS tarif_parkir (
    jenis_kendaraan TEXT NOT NULL PRIMARY KEY CHECK (jenis_kendaraan IN ('Motor', 'Mobil')),
    tarif_per_jam INTEGER NOT NULL CHECK (typeof(tarif_per_jam) = 'integer' AND tarif_per_jam > 0 AND tarif_per_jam <= 9007199254740991)
);

-- @statement

CREATE TABLE IF NOT EXISTS kapasitas_parkir (
    jenis_kendaraan TEXT NOT NULL PRIMARY KEY
        REFERENCES tarif_parkir(jenis_kendaraan) ON UPDATE CASCADE,
    kapasitas INTEGER NOT NULL CHECK (typeof(kapasitas) = 'integer' AND kapasitas >= 0 AND kapasitas <= 9007199254740991)
);

-- @statement

CREATE TABLE IF NOT EXISTS transaksi_parkir (
    id_transaksi TEXT NOT NULL PRIMARY KEY,
    nomor_polisi TEXT NOT NULL CHECK (
        length(nomor_polisi) BETWEEN 3 AND 12
        AND nomor_polisi NOT GLOB '*[^A-Z0-9]*'
    ),
    jenis_kendaraan TEXT NOT NULL
        REFERENCES tarif_parkir(jenis_kendaraan),
    waktu_masuk INTEGER NOT NULL,
    waktu_keluar INTEGER,
    tarif_per_jam_saat_masuk INTEGER NOT NULL
        CHECK (tarif_per_jam_saat_masuk > 0),
    jam_tertagih INTEGER,
    total_biaya INTEGER,
    metode_pembayaran TEXT,
    uang_diterima INTEGER,
    kembalian INTEGER,
    status_parkir TEXT NOT NULL CHECK (status_parkir IN ('Aktif', 'Selesai')),
    status_pembayaran TEXT NOT NULL CHECK (
        status_pembayaran IN ('Belum Bayar', 'Lunas')
    ),
    id_petugas_masuk INTEGER NOT NULL REFERENCES users(id_user),
    id_petugas_keluar INTEGER REFERENCES users(id_user),
    CHECK (waktu_keluar IS NULL OR waktu_keluar >= waktu_masuk),
    CHECK (
        (
            status_parkir = 'Aktif'
            AND status_pembayaran = 'Belum Bayar'
            AND waktu_keluar IS NULL
            AND jam_tertagih IS NULL
            AND total_biaya IS NULL
            AND metode_pembayaran IS NULL
            AND uang_diterima IS NULL
            AND kembalian IS NULL
            AND id_petugas_keluar IS NULL
        )
        OR
        (
            status_parkir = 'Selesai'
            AND status_pembayaran = 'Lunas'
            AND waktu_keluar IS NOT NULL
            AND jam_tertagih IS NOT NULL
            AND typeof(jam_tertagih) = 'integer' AND jam_tertagih >= 1
            AND total_biaya IS NOT NULL
            AND total_biaya = tarif_per_jam_saat_masuk * jam_tertagih
            AND metode_pembayaran IS NOT NULL
            AND metode_pembayaran = 'Tunai'
            AND uang_diterima IS NOT NULL
            AND typeof(uang_diterima) = 'integer' AND uang_diterima >= total_biaya AND uang_diterima <= 9007199254740991
            AND kembalian IS NOT NULL
            AND kembalian = uang_diterima - total_biaya
            AND id_petugas_keluar IS NOT NULL
        )
    )
);

-- @statement

CREATE UNIQUE INDEX IF NOT EXISTS uq_nomor_polisi_aktif
ON transaksi_parkir(nomor_polisi)
WHERE status_parkir = 'Aktif';

-- @statement

CREATE INDEX IF NOT EXISTS ix_transaksi_status_jenis
ON transaksi_parkir(status_parkir, jenis_kendaraan);

-- @statement

CREATE INDEX IF NOT EXISTS ix_transaksi_waktu_keluar
ON transaksi_parkir(waktu_keluar);

-- @statement

DROP TRIGGER IF EXISTS trg_kapasitas_saat_masuk;

-- @statement

CREATE TRIGGER trg_kapasitas_saat_masuk
BEFORE INSERT ON transaksi_parkir
WHEN NEW.status_parkir = 'Aktif'
BEGIN
    SELECT CASE WHEN NOT EXISTS (
        SELECT 1 FROM kapasitas_parkir
        WHERE jenis_kendaraan = NEW.jenis_kendaraan
    ) THEN RAISE(ABORT, 'Kapasitas parkir belum dikonfigurasi') END;
    SELECT CASE WHEN (
        SELECT COUNT(*) FROM transaksi_parkir
        WHERE status_parkir = 'Aktif'
          AND jenis_kendaraan = NEW.jenis_kendaraan
    ) >= (
        SELECT kapasitas FROM kapasitas_parkir
        WHERE jenis_kendaraan = NEW.jenis_kendaraan
    ) THEN RAISE(ABORT, 'Kapasitas parkir penuh') END;
END;

-- @statement

CREATE TRIGGER IF NOT EXISTS trg_kapasitas_tidak_boleh_di_bawah_aktif
BEFORE UPDATE OF kapasitas ON kapasitas_parkir
BEGIN
    SELECT CASE WHEN NEW.kapasitas < (
        SELECT COUNT(*) FROM transaksi_parkir
        WHERE status_parkir = 'Aktif'
          AND jenis_kendaraan = NEW.jenis_kendaraan
    ) THEN RAISE(ABORT, 'Kapasitas lebih kecil dari kendaraan aktif') END;
END;

-- @statement

-- Trigger berikut juga memperketat database lama yang dibuat sebelum seluruh
-- NOT NULL kondisional dicantumkan pada CHECK transaksi selesai.
CREATE TRIGGER IF NOT EXISTS trg_rincian_selesai_lengkap_insert
BEFORE INSERT ON transaksi_parkir
WHEN NEW.status_parkir = 'Selesai' AND (
    NEW.waktu_keluar IS NULL OR NEW.jam_tertagih IS NULL
    OR NEW.total_biaya IS NULL OR NEW.metode_pembayaran IS NULL
    OR NEW.uang_diterima IS NULL OR NEW.kembalian IS NULL
    OR NEW.id_petugas_keluar IS NULL
)
BEGIN
    SELECT RAISE(ABORT, 'Rincian transaksi selesai wajib lengkap');
END;

-- @statement

CREATE TRIGGER IF NOT EXISTS trg_rincian_selesai_lengkap_update
BEFORE UPDATE ON transaksi_parkir
WHEN NEW.status_parkir = 'Selesai' AND (
    NEW.waktu_keluar IS NULL OR NEW.jam_tertagih IS NULL
    OR NEW.total_biaya IS NULL OR NEW.metode_pembayaran IS NULL
    OR NEW.uang_diterima IS NULL OR NEW.kembalian IS NULL
    OR NEW.id_petugas_keluar IS NULL
)
BEGIN
    SELECT RAISE(ABORT, 'Rincian transaksi selesai wajib lengkap');
END;

-- @statement

-- Riwayat tidak dapat diubah/dihapus, bahkan jika query baru ditambahkan kelak.
CREATE TRIGGER IF NOT EXISTS trg_selesai_immutable_update
BEFORE UPDATE ON transaksi_parkir WHEN OLD.status_parkir = 'Selesai'
BEGIN
    SELECT RAISE(ABORT, 'Transaksi selesai tidak boleh diubah');
END;

-- @statement

CREATE TRIGGER IF NOT EXISTS trg_selesai_immutable_delete
BEFORE DELETE ON transaksi_parkir WHEN OLD.status_parkir = 'Selesai'
BEGIN
    SELECT RAISE(ABORT, 'Transaksi selesai tidak boleh dihapus');
END;

-- @statement

CREATE TRIGGER IF NOT EXISTS trg_data_masuk_immutable
BEFORE UPDATE ON transaksi_parkir WHEN
    NEW.id_transaksi != OLD.id_transaksi OR NEW.nomor_polisi != OLD.nomor_polisi
    OR NEW.jenis_kendaraan != OLD.jenis_kendaraan OR NEW.waktu_masuk != OLD.waktu_masuk
    OR NEW.tarif_per_jam_saat_masuk != OLD.tarif_per_jam_saat_masuk
    OR NEW.id_petugas_masuk != OLD.id_petugas_masuk
BEGIN
    SELECT RAISE(ABORT, 'Data kendaraan masuk tidak boleh diubah');
END;
