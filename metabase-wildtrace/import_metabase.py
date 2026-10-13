"""Create saved questions and a dashboard using the Metabase API (stdlib only)."""
import argparse
import getpass
import json
import sys
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse

class API:
    def __init__(self, url):
        self.url=url.rstrip('/')
        self.session=None
    def call(self, method, path, body=None):
        headers={'Content-Type':'application/json'}
        if self.session: headers['X-Metabase-Session']=self.session
        req=Request(self.url+'/api'+path,data=None if body is None else json.dumps(body).encode(),headers=headers,method=method)
        try:
            with urlopen(req,timeout=120) as response:
                data=response.read()
                return json.loads(data) if data else None
        except HTTPError as exc:
            # API errors can contain query details. Do not print raw responses or credentials.
            raise RuntimeError(f'API {method} {path} : HTTP {exc.code}. Vérifier les accès et la documentation /api/docs de cette instance.') from None
        except URLError:
            raise RuntimeError('Metabase inaccessible. Vérifier URL, port et démarrage Docker.') from None

def rows(value):
    if isinstance(value,list): return value
    if isinstance(value,dict) and isinstance(value.get('data'),list): return value['data']
    raise RuntimeError('Format de réponse API inattendu.')

def unique(items,name,collection=None):
    found=[x for x in items if x.get('name')==name and not x.get('archived',False) and (collection is None or x.get('collection_id')==collection)]
    if len(found)>1: raise RuntimeError(f'Plusieurs éléments nommés {name!r} : résoudre les doublons avant de continuer.')
    return found[0] if found else None

def native(database,query):
    return {'database':database,'type':'native','native':{'query':query,'template-tags':{}}}

def place(index):
    # Two cards per row, 24-column dashboard grid.
    return {'row':(index//2)*6,'col':(index%2)*12,'size_x':12,'size_y':6}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url',default='http://localhost:3000')
    parser.add_argument('--database',default='wildtrace',help='Nom affiché dans Metabase, comparaison sans casse')
    parser.add_argument('--database-id',type=int)
    parser.add_argument('--check-only',action='store_true',help='Vérifie toutes les requêtes sans créer de contenu')
    args=parser.parse_args()
    parsed=urlparse(args.url)
    if parsed.scheme not in ('http','https') or not parsed.hostname or parsed.username or parsed.password:
        raise RuntimeError('URL invalide ; ne pas inclure de credentials dans l’URL.')
    if parsed.scheme=='http' and parsed.hostname not in ('localhost','127.0.0.1','::1'):
        raise RuntimeError('Utiliser HTTPS pour une instance distante.')
    questions=json.loads(Path(__file__).with_name('questions.json').read_text())
    api=API(args.url)
    email=input('E-mail du compte administrateur Metabase : ').strip()
    password=getpass.getpass('Mot de passe Metabase (pas celui PostgreSQL) : ')
    api.session=api.call('POST','/session',{'username':email,'password':password})['id']
    del password
    try:
        databases=rows(api.call('GET','/database'))
        matches=[d for d in databases if d['id']==args.database_id] if args.database_id else [d for d in databases if d['name'].casefold()==args.database.casefold()]
        if len(matches)!=1:
            print('Bases disponibles :',[(d['id'],d['name']) for d in databases])
            raise RuntimeError('Choisir la base WildTrace avec --database ou --database-id.')
        database=matches[0]['id']
        if matches[0].get('engine')!='postgres': raise RuntimeError('La source doit être PostgreSQL.')
        # Validate SQL before creating any collection or card. LIMIT 0 checks columns without fetching private rows.
        failures=[]
        for question in questions:
            result=api.call('POST','/dataset',native(database,'SELECT * FROM ('+question['query'].rstrip(';')+') AS validation LIMIT 0'))
            if result.get('status')!='completed': failures.append(question['name'])
        if failures:
            print('Questions incompatibles avec le schéma actuel :\n'+'\n'.join(failures))
            raise RuntimeError('Appliquer le schema.sql enrichi complet avant cet import. Aucun contenu créé.')
        print(f'{len(questions)} requêtes validées.')
        if args.check_only: return
        collection_name='WildTrace — Dataviz'
        collections=rows(api.call('GET','/collection'))
        collection=unique(collections,collection_name)
        if not collection:
            collection=api.call('POST','/collection',{'name':collection_name,'description':'Questions et suivi des données WildTrace. Import généré ; données privées.','color':'#6B8F71'})
        cid=collection['id']
        # Names plus collection scope allow resumption without a local state file.
        existing=rows(api.call('GET','/card?f=all'))
        cards=[]
        for question in questions:
            card=unique(existing,question['name'],cid)
            if card and card.get('dataset_query',{}).get('database')!=database:
                raise RuntimeError('Une question existante utilise une autre base : arrêter pour éviter un mélange.')
            if not card:
                card=api.call('POST','/card',{
                    'name':question['name'],'description':question['description'],
                    'collection_id':cid,'dataset_query':native(database,question['query']),
                    'display':question['display'],'visualization_settings':question['visualization_settings']})
                existing.append(card)
                print('Créée :',question['name'])
            else: print('Conservée :',question['name'])
            cards.append(card)
        title='WildTrace — Suivi et qualité des données'
        dashboards=rows(api.call('GET','/dashboard'))
        dashboard=unique(dashboards,title,cid)
        if not dashboard:
            dashboard=api.call('POST','/dashboard',{'name':title,'collection_id':cid,'description':'Couverture, qualité, synchronisations et exploration. Les synchronisations ne sont pas les traitements WildTrace.','parameters':[]})
        dashboard=api.call('GET','/dashboard/'+str(dashboard['id']))
        dashcards=dashboard.get('dashcards',[])
        present={d.get('card_id') for d in dashcards}
        start=max((d.get('row',0)+d.get('size_y',6) for d in dashcards),default=0)
        added=0
        for card in cards:
            if card['id'] in present: continue
            geometry=place(added);geometry['row']+=start
            dashcards.append({'id':-(added+1),'card_id':card['id'],'series':[],
                              'parameter_mappings':[],'visualization_settings':{},**geometry})
            added+=1
        if added: api.call('PUT','/dashboard/'+str(dashboard['id']),{'dashcards':dashcards})
        print('\nDashboard prêt : '+api.url+'/dashboard/'+str(dashboard['id']))
        print('Les questions et placements existants ont été conservés. Aucun partage public activé.')
    finally:
        try: api.call('DELETE','/session',{'session_id':api.session})
        except RuntimeError: pass

if __name__=='__main__':
    try: main()
    except (RuntimeError,KeyError,ValueError) as exc:
        print('Import arrêté :',exc,file=sys.stderr);sys.exit(1)
