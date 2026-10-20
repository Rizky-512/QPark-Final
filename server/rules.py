"""Aturan SRS. Waktu detik UTC berasal dari server; jam uji hanya diinjeksi oleh tes."""
import re
CAPACITY = 20
RATE = 7000
QUOTE_SECONDS = 300
WINDOW_SECONDS = 900
AUTH_SECONDS = 120
LOGIN_SECONDS = 8 * 3600

class RuleError(Exception):
    def __init__(self, message, code='invalid', status=409):
        super().__init__(message)
        self.code, self.status = code, status

def plate(value):
    if not isinstance(value, str):
        raise RuleError('Nomor polisi wajib diisi.', 'plate', 400)
    value = re.sub(r'\s+', '', value).upper()
    if not re.fullmatch(r'[A-Z0-9]+', value) or len(value) > 32:
        raise RuleError('Nopol harus 1–32 huruf atau angka, tanpa tanda baca.', 'plate', 400)
    return value

def charge(duration, rate=RATE):
    if duration < 0:
        raise RuleError('Waktu masuk tidak valid; durasi negatif.', 'clock', 400)
    hours = max(1, int(duration // 3600))
    return hours, hours * rate
