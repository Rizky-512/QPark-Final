"""Repository SQLite persisten untuk fase prototipe lokal."""

from __future__ import annotations

import logging
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import date, datetime, time
from pathlib import Path
from typing import Iterator

from app.domain.errors import ConflictError, DataAccessError, NotFoundError, ValidationError
from app.domain.models import SlotSummary, Transaction, User


class SQLiteParkingRepository:
    def __init__(self, db_path: str | Path) -> None:
        self.db_path = Path(db_path)
        try:
            self.db_path.parent.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise DataAccessError("Folder database tidak dapat dibuat. Periksa izin folder proyek.") from exc
        self._schema_path = Path(__file__).with_name("schema.sql")

    def initialize(self) -> None:
        """Terapkan skema dan trigger dalam satu transaksi migrasi lokal."""
        with self._connect() as connection:
            connection.executescript("BEGIN IMMEDIATE;\n" + self._schema_path.read_text(encoding="utf-8") + "\nCOMMIT;")

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        """Commit hanya setelah seluruh operasi sukses; rollback jika ada kegagalan."""
        connection = None
        try:
            connection = sqlite3.connect(self.db_path, timeout=10)
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA foreign_keys = ON")
            connection.execute("PRAGMA busy_timeout = 10000")
            yield connection
            connection.commit()
        except sqlite3.IntegrityError:
            if connection:
                connection.rollback()
            raise
        except sqlite3.DatabaseError as exc:
            if connection:
                connection.rollback()
            logging.getLogger(__name__).exception("Operasi SQLite gagal")
            raise DataAccessError(
                "Database tidak dapat dibaca atau disimpan. Periksa izin folder, "
                "ruang penyimpanan, atau aplikasi lain yang memakai database; lalu coba lagi."
            ) from exc
        except Exception:
            if connection:
                connection.rollback()
            raise
        finally:
            if connection:
                connection.close()

    @staticmethod
    def _iso(value: datetime) -> str:
        return value.isoformat(sep=" ", timespec="microseconds")

    @staticmethod
    def _user(row: sqlite3.Row) -> User:
        return User(
            id_user=row["id_user"], nama=row["nama"], username=row["username"],
            role=row["role"], aktif=bool(row["aktif"]),
        )

    @staticmethod
    def _transaction(row: sqlite3.Row) -> Transaction:
        return Transaction(
            id_transaksi=row["id_transaksi"], nomor_polisi=row["nomor_polisi"],
            jenis_kendaraan=row["jenis_kendaraan"],
            waktu_masuk=datetime.fromisoformat(row["waktu_masuk"]),
            waktu_keluar=(datetime.fromisoformat(row["waktu_keluar"]) if row["waktu_keluar"] else None),
            tarif_per_jam_saat_masuk=row["tarif_per_jam_saat_masuk"],
            jam_tertagih=row["jam_tertagih"], total_biaya=row["total_biaya"],
            metode_pembayaran=row["metode_pembayaran"], uang_diterima=row["uang_diterima"],
            kembalian=row["kembalian"], status_parkir=row["status_parkir"],
            status_pembayaran=row["status_pembayaran"], id_petugas_masuk=row["id_petugas_masuk"],
            id_petugas_keluar=row["id_petugas_keluar"],
            nama_petugas_masuk=row["nama_petugas_masuk"] if "nama_petugas_masuk" in row.keys() else "",
            nama_petugas_keluar=row["nama_petugas_keluar"] if "nama_petugas_keluar" in row.keys() else "",
        )

    @staticmethod
    def _transaction_select() -> str:
        return """
            SELECT t.*, masuk.nama AS nama_petugas_masuk,
                   COALESCE(keluar.nama, '') AS nama_petugas_keluar
            FROM transaksi_parkir t
            JOIN users masuk ON masuk.id_user = t.id_petugas_masuk
            LEFT JOIN users keluar ON keluar.id_user = t.id_petugas_keluar
        """

    def seed_defaults(self, admin_hash: str, officer_hash: str) -> None:
        """Isi konfigurasi dan akun demo hanya bila baris belum tersedia."""
        with self._connect() as connection:
            connection.execute(
                "INSERT OR IGNORE INTO tarif_parkir VALUES (?, ?)", ("Motor", 2000)
            )
            connection.execute(
                "INSERT OR IGNORE INTO tarif_parkir VALUES (?, ?)", ("Mobil", 5000)
            )
            connection.execute(
                "INSERT OR IGNORE INTO kapasitas_parkir VALUES (?, ?)", ("Motor", 2)
            )
            connection.execute(
                "INSERT OR IGNORE INTO kapasitas_parkir VALUES (?, ?)", ("Mobil", 1)
            )
            connection.execute(
                """INSERT OR IGNORE INTO users
                   (nama, username, password_hash, role, aktif) VALUES (?, ?, ?, 'Admin', 1)""",
                ("Administrator", "admin", admin_hash),
            )
            connection.execute(
                """INSERT OR IGNORE INTO users
                   (nama, username, password_hash, role, aktif) VALUES (?, ?, ?, 'Petugas', 1)""",
                ("Petugas Demo", "petugas", officer_hash),
            )

    def get_user_for_login(self, username: str) -> tuple[User, str] | None:
        """Ambil hash untuk autentikasi internal; jangan kirim ke UI."""
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM users WHERE username = ?", (username,)
            ).fetchone()
        return (self._user(row), row["password_hash"]) if row else None

    def get_user(self, user_id: int) -> User | None:
        """Baca status akun terkini untuk pemeriksaan otorisasi."""
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM users WHERE id_user = ?", (user_id,)
            ).fetchone()
        return self._user(row) if row else None

    def list_users(self, role: str | None = None) -> list[User]:
        """Baca identitas pengguna tanpa mengembalikan hash."""
        sql = "SELECT * FROM users"
        params: tuple[object, ...] = ()
        if role:
            sql += " WHERE role = ?"
            params = (role,)
        sql += " ORDER BY nama"
        with self._connect() as connection:
            rows = connection.execute(sql, params).fetchall()
        return [self._user(row) for row in rows]

    def create_user(self, nama: str, username: str, password_hash: str, role: str) -> User:
        """Simpan akun baru dan tolak username yang sudah dipakai."""
        try:
            with self._connect() as connection:
                cursor = connection.execute(
                    """INSERT INTO users (nama, username, password_hash, role, aktif)
                       VALUES (?, ?, ?, ?, 1)""",
                    (nama, username, password_hash, role),
                )
                row = connection.execute(
                    "SELECT * FROM users WHERE id_user = ?", (cursor.lastrowid,)
                ).fetchone()
        except sqlite3.IntegrityError as exc:
            if "username" in str(exc).lower() or "unique" in str(exc).lower():
                raise ConflictError("Nama pengguna sudah digunakan.") from exc
            raise ValidationError("Akun tidak dapat disimpan.") from exc
        return self._user(row)

    def set_user_active(self, user_id: int, active: bool) -> None:
        """Aktifkan atau nonaktifkan petugas tanpa menghapus akun."""
        with self._connect() as connection:
            cursor = connection.execute(
                "UPDATE users SET aktif = ? WHERE id_user = ? AND role = 'Petugas'",
                (int(active), user_id),
            )
            if cursor.rowcount != 1:
                raise NotFoundError("Akun petugas tidak ditemukan.")

    def get_slot_summaries(self) -> list[SlotSummary]:
        """Hitung jumlah aktif per jenis dan tolak konfigurasi tidak lengkap."""
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT k.jenis_kendaraan, k.kapasitas, COUNT(t.id_transaksi) AS terisi
                   FROM kapasitas_parkir k
                   LEFT JOIN transaksi_parkir t
                     ON t.jenis_kendaraan = k.jenis_kendaraan
                    AND t.status_parkir = 'Aktif'
                   GROUP BY k.jenis_kendaraan, k.kapasitas
                   ORDER BY CASE k.jenis_kendaraan WHEN 'Motor' THEN 1 ELSE 2 END"""
            ).fetchall()
        if {row["jenis_kendaraan"] for row in rows} != {"Motor", "Mobil"}:
            raise DataAccessError("Konfigurasi kapasitas belum lengkap; slot tidak dapat ditampilkan.")
        if any(row["terisi"] > row["kapasitas"] for row in rows):
            raise DataAccessError("Data kapasitas tidak konsisten dengan kendaraan aktif.")
        return [SlotSummary(row["jenis_kendaraan"], row["kapasitas"], row["terisi"]) for row in rows]

    def get_settings(self) -> dict[str, dict[str, int]]:
        """Baca pasangan tarif dan kapasitas Motor serta Mobil."""
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT t.jenis_kendaraan, t.tarif_per_jam, k.kapasitas
                   FROM tarif_parkir t JOIN kapasitas_parkir k USING (jenis_kendaraan)"""
            ).fetchall()
        if {row["jenis_kendaraan"] for row in rows} != {"Motor", "Mobil"}:
            raise DataAccessError("Konfigurasi tarif dan kapasitas belum lengkap.")
        return {row["jenis_kendaraan"]: {"tarif": row["tarif_per_jam"], "kapasitas": row["kapasitas"]} for row in rows}

    def update_settings(self, vehicle_type: str, capacity: int, rate: int) -> None:
        """Ubah tarif dan kapasitas bersama; rollback bila kapasitas tidak sah."""
        try:
            with self._connect() as connection:
                connection.execute("BEGIN IMMEDIATE")
                connection.execute(
                    "UPDATE tarif_parkir SET tarif_per_jam = ? WHERE jenis_kendaraan = ?",
                    (rate, vehicle_type),
                )
                cursor = connection.execute(
                    "UPDATE kapasitas_parkir SET kapasitas = ? WHERE jenis_kendaraan = ?",
                    (capacity, vehicle_type),
                )
                if cursor.rowcount != 1:
                    raise NotFoundError("Jenis kendaraan tidak ditemukan.")
        except sqlite3.IntegrityError as exc:
            if "Kapasitas lebih kecil" in str(exc):
                raise ValidationError("Kapasitas tidak boleh di bawah jumlah kendaraan aktif.") from exc
            raise ValidationError("Kapasitas atau tarif tidak valid; perubahan dibatalkan.") from exc

    def create_entry(self, plate: str, vehicle_type: str, entered_at: datetime, officer_id: int) -> Transaction:
        """Kunci tulis, cek petugas, ambil tarif, lalu simpan satu kunjungan."""
        transaction_id = f"TRX-{entered_at:%Y%m%d}-{uuid.uuid4().hex[:12].upper()}"
        try:
            with self._connect() as connection:
                connection.execute("BEGIN IMMEDIATE")
                user = connection.execute(
                    "SELECT role, aktif FROM users WHERE id_user = ?", (officer_id,)
                ).fetchone()
                if not user or not user["aktif"] or user["role"] != "Petugas":
                    raise ValidationError("Sesi petugas tidak aktif atau tidak berwenang.")
                rate = connection.execute(
                    "SELECT tarif_per_jam FROM tarif_parkir WHERE jenis_kendaraan = ?",
                    (vehicle_type,),
                ).fetchone()
                if not rate:
                    raise ValidationError("Tarif kendaraan belum dikonfigurasi.")
                connection.execute(
                    """INSERT INTO transaksi_parkir (
                           id_transaksi, nomor_polisi, jenis_kendaraan, waktu_masuk,
                           tarif_per_jam_saat_masuk, status_parkir, status_pembayaran,
                           id_petugas_masuk
                       ) VALUES (?, ?, ?, ?, ?, 'Aktif', 'Belum Bayar', ?)""",
                    (transaction_id, plate, vehicle_type, self._iso(entered_at), rate[0], officer_id),
                )
                row = connection.execute(self._transaction_select() + " WHERE t.id_transaksi = ?",
                                         (transaction_id,)).fetchone()
                transaction = self._transaction(row)
        except sqlite3.IntegrityError as exc:
            message = str(exc)
            if "uq_nomor_polisi_aktif" in message or "UNIQUE constraint" in message:
                raise ConflictError("Nomor polisi tersebut masih memiliki transaksi aktif.") from exc
            if "Kapasitas parkir penuh" in message:
                raise ConflictError(f"Kapasitas parkir {vehicle_type.lower()} penuh.") from exc
            if "belum dikonfigurasi" in message:
                raise ValidationError("Kapasitas kendaraan belum dikonfigurasi.") from exc
            logging.getLogger(__name__).exception("Constraint pencatatan masuk gagal")
            raise ValidationError("Transaksi masuk gagal divalidasi; tidak ada data yang disimpan.") from exc
        return transaction

    def get_transaction(self, transaction_id: str) -> Transaction | None:
        """Ambil transaksi beserta nama petugas melalui query parameter."""
        with self._connect() as connection:
            row = connection.execute(
                self._transaction_select() + " WHERE t.id_transaksi = ?", (transaction_id,)
            ).fetchone()
        return self._transaction(row) if row else None

    def list_active(self, query: str = "") -> list[Transaction]:
        """Cari transaksi aktif menggunakan pelat atau ID literal."""
        normalized = "".join(query.upper().split())
        like = "%" + normalized.replace("!", "!!").replace("%", "!%").replace("_", "!_") + "%"
        with self._connect() as connection:
            rows = connection.execute(
                self._transaction_select()
                + """ WHERE t.status_parkir = 'Aktif'
                       AND (? = '' OR t.nomor_polisi LIKE ? ESCAPE '!' OR upper(t.id_transaksi) LIKE ? ESCAPE '!' )
                       ORDER BY t.waktu_masuk DESC""",
                (normalized, like, like),
            ).fetchall()
        return [self._transaction(row) for row in rows]

    def finish_transaction(self, transaction_id: str, exited_at: datetime, billed_hours: int, total: int, received: int, officer_id: int) -> Transaction:
        """Selesaikan transaksi satu kali dan baca bukti sebelum commit."""
        try:
            with self._connect() as connection:
                connection.execute("BEGIN IMMEDIATE")
                user = connection.execute(
                    "SELECT role, aktif FROM users WHERE id_user = ?", (officer_id,)
                ).fetchone()
                if not user or not user["aktif"] or user["role"] != "Petugas":
                    raise ValidationError("Sesi petugas tidak aktif atau tidak berwenang.")
                cursor = connection.execute(
                    """UPDATE transaksi_parkir SET
                           waktu_keluar = ?, jam_tertagih = ?, total_biaya = ?,
                           metode_pembayaran = 'Tunai', uang_diterima = ?, kembalian = ?,
                           status_parkir = 'Selesai', status_pembayaran = 'Lunas',
                           id_petugas_keluar = ?
                       WHERE id_transaksi = ? AND status_parkir = 'Aktif'
                         AND status_pembayaran = 'Belum Bayar'""",
                    (self._iso(exited_at), billed_hours, total, received, received - total, officer_id, transaction_id),
                )
                if cursor.rowcount != 1:
                    raise ConflictError("Transaksi sudah selesai atau tidak ditemukan.")
                row = connection.execute(self._transaction_select() + " WHERE t.id_transaksi = ?",
                                         (transaction_id,)).fetchone()
                result = self._transaction(row)
            return result
        except sqlite3.IntegrityError as exc:
            logging.getLogger(__name__).exception("Constraint pembayaran gagal")
            raise ValidationError("Pembayaran gagal divalidasi. Transaksi tetap aktif; periksa data dan coba lagi.") from exc

    def list_history(self, start: date, end: date, vehicle_type: str | None = None, query: str = "") -> list[Transaction]:
        """Ambil transaksi selesai dalam seluruh hari awal sampai akhir."""
        begin = datetime.combine(start, time.min)
        finish = datetime.combine(end, time.max)
        normalized = "".join(query.upper().split())
        like = "%" + normalized.replace("!", "!!").replace("%", "!%").replace("_", "!_") + "%"
        # Awal tanpa pecahan juga mencakup database lama yang menyimpan presisi detik.
        params: list[object] = [begin.isoformat(sep=" "), self._iso(finish), normalized, like, like]
        sql = self._transaction_select() + """ WHERE t.status_parkir = 'Selesai'
            AND t.waktu_keluar >= ? AND t.waktu_keluar <= ?
            AND (? = '' OR t.nomor_polisi LIKE ? ESCAPE '!' OR upper(t.id_transaksi) LIKE ? ESCAPE '!' )"""
        if vehicle_type:
            sql += " AND t.jenis_kendaraan = ?"
            params.append(vehicle_type)
        sql += " ORDER BY t.waktu_keluar DESC"
        with self._connect() as connection:
            rows = connection.execute(sql, params).fetchall()
        return [self._transaction(row) for row in rows]

    def revenue_summary(self, start: date, end: date, vehicle_type: str | None = None) -> tuple[int, int]:
        """Jumlahkan total biaya transaksi lunas, bukan uang diterima."""
        begin = datetime.combine(start, time.min)
        finish = datetime.combine(end, time.max)
        params: list[object] = [begin.isoformat(sep=" "), self._iso(finish)]
        sql = """SELECT COUNT(*) AS jumlah, COALESCE(SUM(total_biaya), 0) AS total
                 FROM transaksi_parkir WHERE status_pembayaran = 'Lunas'
                   AND waktu_keluar >= ? AND waktu_keluar <= ?"""
        if vehicle_type:
            sql += " AND jenis_kendaraan = ?"
            params.append(vehicle_type)
        with self._connect() as connection:
            row = connection.execute(sql, params).fetchone()
        return row["jumlah"], row["total"]

