"""Sesi proses lokal yang dibagikan service pada satu instance repository."""
from __future__ import annotations

from threading import RLock
from weakref import WeakKeyDictionary
from app.data.repository import ParkingRepository

_LOCK = RLock()
_SESSIONS: WeakKeyDictionary = WeakKeyDictionary()


def activate(repository: ParkingRepository, user_id: int) -> None:
    """Daftarkan pengguna hanya setelah autentikasi berhasil."""
    with _LOCK:
        _SESSIONS.setdefault(repository, set()).add(user_id)


def revoke(repository: ParkingRepository, user_id: int) -> None:
    """Cabut hak akses sesi; tidak mengubah akun atau transaksi."""
    with _LOCK:
        _SESSIONS.get(repository, set()).discard(user_id)


def is_active(repository: ParkingRepository, user_id: int | None) -> bool:
    with _LOCK:
        return user_id in _SESSIONS.get(repository, set())
