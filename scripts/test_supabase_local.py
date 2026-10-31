"""Run migrations/security regression in a fresh DB on a disposable Docker Postgres."""
import argparse
from pathlib import Path
import subprocess
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    database = 'qpark_test_' + uuid.uuid4().hex[:12]
    command = ['docker', 'exec', '-i', args.container, 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1']
    def sql(content, db='postgres'):
        result = subprocess.run(command + ['-d', db], input=content, text=True,
                                encoding='utf-8', capture_output=True, check=True)
        return result.stdout
    sql('CREATE DATABASE ' + database)
    try:
        # Minimal Supabase auth surface for migration tests, not a production emulator.
        sql('''
          DO $$ BEGIN CREATE ROLE anon; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
          DO $$ BEGIN CREATE ROLE authenticated; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
          DO $$ BEGIN CREATE ROLE service_role; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
          CREATE SCHEMA auth;
          CREATE SCHEMA extensions;
          CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
          CREATE TABLE auth.users(id uuid primary key, email text, raw_user_meta_data jsonb default '{}');
          CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS
            $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
          GRANT USAGE ON SCHEMA public,auth TO anon,authenticated;
        ''', database)
        for migration in sorted((root/'supabase/migrations').glob('*.sql')):
            sql(migration.read_text(encoding='utf-8'), database)
            print('PASS', migration.name, flush=True)
        sql((root/'supabase/tests/customer_access.sql').read_text(encoding='utf-8'), database)
        print('PASS customer ownership, private RPC grants, payment replay, history isolation and expiry', flush=True)
    except subprocess.CalledProcessError as error:
        print(error.stderr)
        raise
    finally:
        # Only the uniquely named database created by this invocation is removed.
        sql('DROP DATABASE ' + database)


if __name__ == '__main__':
    main()
