import argparse
import json
import os
import time
from pathlib import Path
import oci
import psycopg
from psycopg.types.json import Jsonb
from model import normalize, fingerprint


def sync():
    config = oci.config.from_file(os.environ.get('OCI_CONFIG_FILE','/oci/config'), os.environ.get('OCI_PROFILE','DEFAULT'))
    client = oci.object_storage.ObjectStorageClient(config, retry_strategy=oci.retry.DEFAULT_RETRY_STRATEGY)
    namespace = os.environ.get('OCI_NAMESPACE') or client.get_namespace().data
    sources = [(os.getenv('CONTEXT_BUCKET','wildtrace-contextualized'), 'contextualized_daily_', 'contextualized'),
               (os.getenv('ENV_BUCKET','wildtrace-environmental'), 'collected/to_compute/', 'pending'),
               (os.getenv('ENV_BUCKET','wildtrace-environmental'), 'collected/computed/', 'computed'),
               (os.getenv('BIO_BUCKET','wildtrace-biological'), 'collected/computed/biological_daily_', 'biological')]
    imported = errors = 0
    with psycopg.connect('') as db:
        db.execute(Path('sql/schema.sql').read_text())
        db.execute('INSERT INTO settings VALUES(true,%s,%s) ON CONFLICT(id) DO UPDATE SET start_day=excluded.start_day,report_timezone=excluded.report_timezone', (os.getenv('START_DAY','2026-10-01'),os.getenv('REPORT_TIMEZONE','Europe/Paris')))
        run = db.execute('INSERT INTO sync_runs DEFAULT VALUES RETURNING id').fetchone()[0]
        db.commit()
        # Serialize imports. Avoid overlapping scheduler/manual executions.
        if not db.execute('SELECT pg_try_advisory_lock(78261012)').fetchone()[0]:
            db.execute("UPDATE sync_runs SET status='skipped_concurrent',finished_at=now() WHERE id=%s",(run,));db.commit();return
        for bucket in dict.fromkeys(s[0] for s in sources):
            scan_ok = True
            for _, prefix, kind in [s for s in sources if s[0]==bucket]:
                start = None
                try:
                    while True:
                        params = {'prefix':prefix,'fields':'name,etag'}
                        if start: params['start']=start
                        page = client.list_objects(namespace,bucket,**params).data
                        for obj in page.objects:
                            if not obj.name.endswith('.json'): continue
                            previous = db.execute('SELECT etag,status FROM objects WHERE bucket=%s AND name=%s',(bucket,obj.name)).fetchone()
                            if previous and previous==(obj.etag,'ok'):
                                db.execute('UPDATE objects SET last_seen_run=%s WHERE bucket=%s AND name=%s',(run,bucket,obj.name));db.commit();continue
                            try:
                                response = client.get_object(namespace,bucket,obj.name)
                                try:
                                    doc = json.loads(response.data.content.decode('utf-8-sig'))
                                    etag = response.headers['etag']
                                finally: response.data.close()
                                entries = normalize(kind,doc)
                                with db.transaction():
                                    db.execute("INSERT INTO objects VALUES(%s,%s,%s,%s,'ok',now(),%s,NULL) ON CONFLICT(bucket,name) DO UPDATE SET etag=excluded.etag,kind=excluded.kind,status='ok',imported_at=now(),last_seen_run=excluded.last_seen_run,error=NULL",(bucket,obj.name,etag,kind,run))
                                    db.execute('DELETE FROM records WHERE bucket=%s AND name=%s',(bucket,obj.name))
                                    for i,(record_kind,day,row) in enumerate(entries):
                                        db.execute('INSERT INTO records VALUES(%s,%s,%s,%s,%s,%s,%s)',(bucket,obj.name,i,record_kind,day,fingerprint(row),Jsonb(row)))
                                db.commit();imported+=1
                            except Exception as exc:
                                db.rollback();errors+=1
                                # Do not expose OCI request URLs, credentials or response bodies.
                                reason = type(exc).__name__
                                if isinstance(exc,(ValueError,KeyError,TypeError)): reason += ': schéma ou date invalide'
                                db.execute("INSERT INTO objects VALUES(%s,%s,%s,%s,'error',now(),%s,%s) ON CONFLICT(bucket,name) DO UPDATE SET status='error',last_seen_run=excluded.last_seen_run,error=excluded.error",(bucket,obj.name,obj.etag,kind,run,reason));db.commit()
                                print('Objet non importé:',bucket,obj.name,reason,flush=True)
                        start = page.next_start_with
                        if not start: break
                except Exception as exc:
                    db.rollback();errors+=1;scan_ok=False
                    print('Listing échoué:',bucket,prefix,type(exc).__name__,flush=True)
            db.execute('INSERT INTO bucket_scans VALUES(%s,%s,%s)',(run,bucket,scan_ok))
            if scan_ok:
                # Deleted/moved source objects no longer contribute to current coverage.
                db.execute("UPDATE objects SET status='absent',error='Absent du dernier listing complet' WHERE bucket=%s AND last_seen_run<>%s",(bucket,run))
            db.commit()
        db.execute('UPDATE sync_runs SET finished_at=now(),status=%s,imported=%s,errors=%s WHERE id=%s',('success' if not errors else 'partial',imported,errors,run));db.commit()
    print(f'Synchronisation: {imported} fichiers importés, {errors} erreurs.',flush=True)
    return errors

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--watch',action='store_true');args=parser.parse_args()
    while True:
        try:
            errors=sync()
            if not args.watch: raise SystemExit(1 if errors else 0)
        except Exception as exc:
            print('Synchronisation interrompue:',type(exc).__name__,flush=True)
            if not args.watch: raise SystemExit(1)
        time.sleep(max(60,int(os.getenv('SYNC_INTERVAL_SECONDS','900'))))
