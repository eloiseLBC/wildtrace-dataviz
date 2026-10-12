"""Generate local settings without external dependencies."""
from pathlib import Path
import secrets
p = Path('.env')
if p.exists():
    raise SystemExit('.env existe déjà : aucune modification.')
p.write_text('POSTGRES_PASSWORD=' + secrets.token_hex(24) + '\n' +
             'OCI_CONFIG_DIR=' + str(Path.home() / '.oci') + '\n' +
             'OCI_PROFILE=DEFAULT\nOCI_NAMESPACE=\nSTART_DAY=2026-10-01\n'
             'REPORT_TIMEZONE=Europe/Paris\nSYNC_INTERVAL_SECONDS=900\n'
             'CONTEXT_BUCKET=wildtrace-contextualized\n'
             'ENV_BUCKET=wildtrace-environmental\nBIO_BUCKET=wildtrace-biological\n')
p.chmod(0o600)
print('.env créé. Vérifier OCI_CONFIG_DIR avant le démarrage.')
