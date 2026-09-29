"""Kesalahan bisnis yang aman ditampilkan kepada pengguna."""


class ParkingError(Exception):
    """Dasar semua kesalahan bisnis aplikasi."""


class ValidationError(ParkingError):
    pass


class AuthenticationError(ParkingError):
    pass


class AuthorizationError(ParkingError):
    pass


class NotFoundError(ParkingError):
    pass


class ConflictError(ParkingError):
    pass


class PriceChangedError(ParkingError):
    def __init__(self, new_total: int) -> None:
        self.new_total = new_total
        super().__init__(
            "Estimasi biaya berubah karena melewati batas jam. "
            "Periksa total baru, lalu konfirmasi kembali."
        )


class DataAccessError(ParkingError):
    """Database tidak dapat digunakan; rincian teknis hanya dicatat di log."""
