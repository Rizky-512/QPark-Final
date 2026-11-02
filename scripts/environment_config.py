"""Validate explicit build profiles without reading implicit local secrets."""
import json
from pathlib import Path


def read_profile(path, environment, comparison=None):
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    if environment not in ('demo', 'test') or data.get('QPARK_ENV') != environment:
        raise ValueError('QPARK_ENV pada berkas harus sama dengan environment yang dipilih.')
    if bool(data.get('SUPABASE_URL')) != bool(data.get('SUPABASE_PUBLISHABLE_KEY')):
        raise ValueError('URL dan publishable key Supabase harus berpasangan.')
    if data.get('SUPABASE_URL') and environment == 'test' and comparison is None:
        raise ValueError('Build Supabase pengujian memerlukan --demo-config untuk memastikan proyek terpisah.')
    if comparison is not None:
        demo = json.loads(Path(comparison).read_text(encoding='utf-8'))
        if demo.get('QPARK_ENV') != 'demo':
            raise ValueError('Berkas pembanding harus QPARK_ENV=demo.')
        target = data.get('SUPABASE_URL') or data.get('API_BASE_URL')
        other = demo.get('SUPABASE_URL') or demo.get('API_BASE_URL')
        if target and other and target.rstrip('/') == other.rstrip('/'):
            raise ValueError('Endpoint demo dan pengujian tidak boleh sama.')
    return data
