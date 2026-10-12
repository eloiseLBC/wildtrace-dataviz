import hashlib
import json
from datetime import datetime, date
from zoneinfo import ZoneInfo

FIELDS = ('temperature', 'humidity', 'luminosity', 'concentration_co2')

def day_of(row):
    value = row.get('local_timestamp') or row.get('timestamp')
    if not isinstance(value, str):
        raise ValueError('timestamp absent')
    try:
        dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError:
        dt = datetime.strptime(value, '%d-%m-%Y %H:%M:%S')
    if dt.tzinfo is not None:
        dt = dt.astimezone(ZoneInfo(row['timezone']))
    return dt.date()

def normalize(kind, doc):
    entries = []
    if kind == 'contextualized':
        d = date.fromisoformat(doc['date'])
        rows = doc['environmental']
        bio = doc['biological']
        if not isinstance(rows, list) or not rows or not isinstance(bio, dict) or bio.get('date') != d.isoformat():
            raise ValueError('document contextualisé incomplet ou dates incompatibles')
        for row in rows:
            if day_of(row) != d:
                raise ValueError('mesure environnementale hors de la journée')
            entries.append(('context_environment', d, row))
        entries.append(('context_biological', d, bio))
    elif kind == 'biological':
        if not isinstance(doc, dict):
            raise ValueError('objet biologique attendu')
        entries.append((kind, date.fromisoformat(doc['date']), doc))
    else:
        rows = [doc] if isinstance(doc, dict) else doc
        if not isinstance(rows, list) or not rows:
            raise ValueError('liste non vide attendue')
        for row in rows:
            entries.append((kind, day_of(row), row))
    return entries

def fingerprint(row):
    return hashlib.sha256(json.dumps(row,sort_keys=True,ensure_ascii=False,allow_nan=False).encode()).hexdigest()
