"""Server demo QPark: API + hasil build Flutter pada origin yang sama."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import argparse
import getpass
import json
import sqlite3
import ssl
import sys
import threading
import webbrowser
from .store import Store
from .rules import RuleError

ROOT=Path(__file__).resolve().parents[1]

class Handler(SimpleHTTPRequestHandler):
    extensions_map={**SimpleHTTPRequestHandler.extensions_map,'.wasm':'application/wasm','.mjs':'text/javascript'}
    def __init__(self,*args,store,origins=(),**kwargs):
        self.store,self.origins=store,set(origins)
        super().__init__(*args,**kwargs)
    def log_message(self,fmt,*args):
        # HTTP URLs can include plate numbers. Do not log queries/payloads/tokens.
        pass
    def end_headers(self):
        origin=self.headers.get('Origin')
        if origin and origin in self.origins:
            self.send_header('Access-Control-Allow-Origin',origin)
            self.send_header('Vary','Origin')
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Referrer-Policy','no-referrer')
        self.send_header('Cross-Origin-Opener-Policy','same-origin')
        self.send_header('Cross-Origin-Embedder-Policy','require-corp')
        super().end_headers()
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Methods','GET,POST,OPTIONS')
        self.send_header('Access-Control-Allow-Headers','Content-Type,Authorization')
        self.end_headers()
    def _api(self):
        try:
            data={}
            if self.command=='POST':
                if 'application/json' not in self.headers.get('Content-Type',''):
                    raise RuleError('Gunakan JSON.','content_type',415)
                size=int(self.headers.get('Content-Length','0'))
                if size<=0 or size>65536:raise RuleError('Ukuran permintaan tidak sah.','payload',400)
                data=json.loads(self.rfile.read(size))
            token=self.headers.get('Authorization','').removeprefix('Bearer ')
            result=self.store.dispatch(self.command,self.path,data,token)
            status=200
        except RuleError as e:
            status=e.status;result={'error':str(e),'code':e.code}
        except (ValueError,TypeError,UnicodeError):
            status=400;result={'error':'Permintaan tidak valid.','code':'payload'}
        except sqlite3.Error:
            status=503;result={'error':'Penyimpanan sedang sibuk. Coba lagi dengan operasi yang sama.','code':'storage'}
        except Exception:
            status=500;result={'error':'Kesalahan internal server. Coba lagi.','code':'server'}
        encoded=json.dumps(result,separators=(',',':')).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Content-Length',str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)
    def do_GET(self):
        if urlsplit(self.path).path.startswith('/api/'):
            return self._api()
        # Only the selected compiled web directory is served, never server/data/docs.
        if '..' in urlsplit(self.path).path.split('/'):
            return self.send_error(404)
        super().do_GET()
    def do_POST(self):
        if self.path.startswith('/api/'):
            return self._api()
        self.send_error(404)

def create_server(store,host='127.0.0.1',port=7357,directory=None,origins=()):
    return ThreadingHTTPServer((host,port),partial(Handler,store=store,origins=origins,directory=str(directory or ROOT/'rilis/web')))

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--host',default='127.0.0.1')
    p.add_argument('--port',type=int,default=7357)
    p.add_argument('--db',type=Path,default=ROOT/'data/qpark_server_v3.db')
    p.add_argument('--directory',type=Path,default=ROOT/'rilis/web')
    p.add_argument('--open',action='store_true')
    p.add_argument('--add-officer',action='store_true')
    p.add_argument('--disable-simulator',action='store_true')
    p.add_argument('--allow-origin',action='append',default=[])
    p.add_argument('--cert',type=Path)
    p.add_argument('--key',type=Path)
    args=p.parse_args()
    if bool(args.cert)!=bool(args.key):p.error('--cert dan --key harus berpasangan')
    store=Store(args.db,simulation=not args.disable_simulator)
    if args.add_officer:
        store.add_officer(input('Username petugas: '),getpass.getpass('Password (minimal 8 karakter): '))
        print('Akun tersimpan.');return 0
    print('Akun demo awal: admin / admin123 dan petugas / petugas123.\nPassword hanya disetel pada pemasangan/migrasi v4 pertama.',flush=True)
    if not (args.directory/'index.html').exists():
        print('Build web belum tersedia. API tetap aktif; jalankan scripts/build_release.py untuk build Flutter.',flush=True)
    try:server=create_server(store,args.host,args.port,args.directory,args.allow_origin)
    except OSError as e:
        print(f'Tidak dapat membuka port {args.port}: {e}. Tutup server lama atau pilih --port lain.');return 1
    scheme='http'
    if args.cert:
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(args.cert,args.key)
        server.socket=context.wrap_socket(server.socket,server_side=True);scheme='https'
    url=f'{scheme}://localhost:{server.server_port}/'
    print(f'QPark: {url}\nDatabase: {args.db}\nBiarkan terminal terbuka. Ctrl+C untuk berhenti.',flush=True)
    if args.host!='127.0.0.1' and not args.cert:
        print('HTTP LAN hanya untuk demo jaringan tepercaya. Kamera browser HP dan akses lintas jaringan memerlukan HTTPS.',flush=True)
    if args.open:threading.Timer(.8,lambda:webbrowser.open(url)).start()
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close()
    return 0

if __name__=='__main__':sys.exit(main())
