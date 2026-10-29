"""Run with python -m qpark_ml; all output files are create-only."""
import argparse
import json
from pathlib import Path
import sqlite3
import sys
import time
from .data import History, read_sqlite
from .model import predict, train
from .simulation import generate, upload_sql


def read_json(path):
    value = json.loads(Path(path).read_text(encoding='utf-8'))
    if not isinstance(value, dict):
        raise ValueError('Input harus objek JSON.')
    return value


def write_new(path, value):
    text = value if isinstance(value, str) else json.dumps(value, indent=2, allow_nan=False)
    with Path(path).open('x', encoding='utf-8') as f:
        f.write(text + '\n')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    demo = sub.add_parser('simulate')
    demo.add_argument('--out', required=True)
    demo.add_argument('--days', type=int, default=56)
    demo.add_argument('--seed', type=int, default=512)
    demo.add_argument('--start', default='2026-08-24T00:00:00+07:00')
    export = sub.add_parser('extract')
    export.add_argument('--db', required=True)
    export.add_argument('--coverage', required=True)
    export.add_argument('--out', required=True)
    fit = sub.add_parser('train')
    fit.add_argument('--input', required=True)
    fit.add_argument('--until', help='ISO cutoff target, timezone required; reserve later data for prediction.')
    fit.add_argument('--out', required=True)
    infer = sub.add_parser('predict')
    infer.add_argument('--input', required=True)
    infer.add_argument('--model', required=True, help='JSON output of train')
    infer.add_argument('--as-of', required=True)
    sql = sub.add_parser('supabase-sql')
    sql.add_argument('--input', required=True)
    sql.add_argument('--run-id', required=True)
    sql.add_argument('--out', required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == 'simulate':
            source = generate(args.start, args.days, args.seed)
            History(source, time.time())
            write_new(args.out, source)
            print(json.dumps(dict(status='ok', source_kind='simulation', sessions=len(source['sessions']))))
        elif args.command == 'extract':
            source = read_sqlite(args.db, read_json(args.coverage))
            history = History(source, time.time())
            write_new(args.out, source)
            print(json.dumps(dict(status='ok' if history.entered else 'insufficient_data',
                                  sessions=len(history.entered), source_kind=history.kind)))
        elif args.command == 'train':
            report, model = train(History(read_json(args.input), time.time()), args.until)
            write_new(args.out, dict(report=report, model=model))
            print(json.dumps(report, allow_nan=False))
        elif args.command == 'predict':
            model = read_json(args.model).get('model')
            result = dict(status='model_unavailable') if model is None else predict(
                model, History(read_json(args.input), time.time()), args.as_of)
            print(json.dumps(result, allow_nan=False))
        else:
            source = read_json(args.input)
            History(source, time.time())
            write_new(args.out, upload_sql(source, args.run_id))
            print(json.dumps(dict(status='prepared', uploaded=False)))
        return 0
    except (ValueError, TypeError, KeyError, OSError, sqlite3.Error, ImportError, OverflowError) as exc:
        # Do not print SQL payloads, file contents, credentials or visit identifiers.
        print(json.dumps(dict(status='error', error_type=type(exc).__name__,
                              message='Periksa input, coverage, file output baru, dan dependensi ML.')), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
