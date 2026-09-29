"""Satu titik pemilihan backend dan penyiapan database awal."""
from app.config import AppConfig
from app.data.repository import ParkingRepository
from app.data.sqlite_repository import SQLiteParkingRepository
from app.domain.errors import ValidationError
from app.logic.security import hash_password


def create_repository(config: AppConfig) -> ParkingRepository:
    """Buat SQLite persisten; backend lain ditolak sampai diimplementasikan."""
    if config.backend != "sqlite":
        raise ValidationError("Backend belum didukung. Gunakan DB_BACKEND=sqlite.")
    repository = SQLiteParkingRepository(config.database_path)
    repository.initialize()
    # Kredensial demonstrasi sesuai SRS; bukan secret layanan eksternal.
    if not repository.get_user_for_login("admin") or not repository.get_user_for_login("petugas"):
        repository.seed_defaults(hash_password("Admin123!"), hash_password("Petugas123!"))
    return repository
