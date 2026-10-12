# WildTrace Dataviz — démarrage local

Ce dossier autonome lit les buckets OCI existants et alimente PostgreSQL pour Metabase.
Il peut être placé à côté de WildTrace ou dans un sous-dossier, sans modifier WildTrace.
Aucun nouveau bucket n'est nécessaire. Aucune écriture, suppression ou déplacement dans OCI.

## 1. Préparer

Installer Docker Desktop (ou Docker Engine + Compose sous Linux) et Python 3.
Dans un terminal, se placer dans ce dossier décompressé, puis :

```sh
python3 configure.py
```

Cela crée `.env` avec un mot de passe aléatoire. Vérifier les noms des buckets,
`START_DAY`, `REPORT_TIMEZONE` et `OCI_CONFIG_DIR`. Le démarrage est prévu au
1er octobre 2026, conformément à la politique de la branche develop consultée.
Le fuseau de rapport détermine la journée en cours ; les dates des mesures restent
celles du fuseau de chaque mesure. Les journées actuelles sont exclues des compteurs
« manquants ». Modifier START_DAY si ta période attendue est différente.

## 2. Configurer OCI

Réutiliser une configuration OCI valide avec profil DEFAULT (ou modifier OCI_PROFILE).
`OCI_CONFIG_DIR` désigne le dossier contenant `config` et la clé privée.
Le conteneur monte ce dossier en lecture seule à `/oci`.
Dans le fichier config utilisé pour ce dossier, le chemin de la clé doit donc être :

```ini
[DEFAULT]
user=ocid1.user.REMPLACER
fingerprint=REMPLACER
tenancy=ocid1.tenancy.REMPLACER
region=eu-paris-1
key_file=/oci/oci_api_key.pem
```

Si ton config existant sert aussi à WildTrace avec un chemin différent, créer un
DOSSIER OCI dédié et y copier config et clé, puis pointer OCI_CONFIG_DIR dessus.
Ne pas modifier le fichier d'origine. Ne jamais ajouter clés ou .env dans Git.
Les clés protégées par phrase secrète nécessitent une configuration supplémentaire ;
ce kit suppose une clé OCI utilisable par le SDK sans interaction.

Le compte OCI doit pouvoir lister et lire les objets des trois buckets. Exemple de
politique à adapter avec ton administrateur, ton groupe et ton compartiment :

```text
Allow group MON_GROUPE to read objects in compartment MON_COMPARTIMENT where target.bucket.name = 'wildtrace-contextualized'
Allow group MON_GROUPE to read objects in compartment MON_COMPARTIMENT where target.bucket.name = 'wildtrace-environmental'
Allow group MON_GROUPE to read objects in compartment MON_COMPARTIMENT where target.bucket.name = 'wildtrace-biological'
```

Renseigner OCI_NAMESPACE dans .env si nécessaire. Sinon le SDK le récupère.

## 3. Démarrer et importer

```sh
docker compose up -d postgres metabase
docker compose --profile sync run --rm sync
```

Le premier import lit tous les JSON des préfixes sélectionnés, archives computed
incluses, pour retrouver les étapes historiques. Les imports suivants ne relisent
que les objets nouveaux/modifiés (ETag). Un objet invalide est retenté.
Les données generated/ ne sont pas importées. Le coût éventuel est celui des lectures
et transferts OCI, en plus de tes ressources existantes.

Pour une synchronisation toutes les 15 minutes, ordinateur et Docker allumés :

```sh
docker compose --profile sync run -d --name wildtrace-sync sync --watch
```

Arrêter cette boucle : `docker stop wildtrace-sync` puis `docker rm wildtrace-sync`.
Les exécutions simultanées sont évitées par un verrou PostgreSQL.

## 4. Configurer Metabase une seule fois

Ouvrir http://localhost:3000 et créer le compte administrateur local.
Ajouter une source **PostgreSQL** nommée WildTrace avec :

| Paramètre | Valeur |
|---|---|
| Hôte | postgres |
| Port | 5432 |
| Base | wildtrace |
| Utilisateur | wildtrace |
| Mot de passe | POSTGRES_PASSWORD du fichier .env |
| SSL | désactivé pour ce réseau Docker local |

L'utilisateur proposé est adapté à une installation personnelle locale. Pour une
installation partagée, créer un utilisateur SELECT seulement et configurer HTTPS.
La base `metabase` stocke les comptes et dashboards ; ne pas la choisir comme source.

Après le premier import, laisser Metabase synchroniser le schéma ou relancer cette
synchronisation dans Administration > Bases de données.
Créer un dashboard « WildTrace — suivi et qualité ».
Ouvrir `sql/dashboard.sql` : pour chaque requête, créer une nouvelle question SQL,
choisir WildTrace, copier UNE requête, exécuter, choisir le graphique indiqué,
enregistrer et ajouter au dashboard. Les 12 requêtes sont prêtes ; la disposition
et la création des questions dans Metabase sont manuelles, sans script API fragile.
Tu pourras ensuite modifier tes graphiques directement dans Metabase.

## Ce que les indicateurs signifient

- « Calculé » : des données sont présentes dans collected/computed/ ou ses archives.
- « Contextualisation disponible » : un JSON de sortie a été validé et importé.
  Cela ne prouve pas une journée complète : une seule mesure peut suffire.
- Les dates manquantes sont comparées au calendrier attendu à partir de START_DAY.
  Une pause volontaire de collecte apparaîtra aussi comme une absence.
- Plusieurs fichiers pour le même jour comptent comme un seul jour. Les mesures
  contextualisées strictement identiques sont dédupliquées pour les agrégats,
  même si elles apparaissent dans plusieurs parties. Le JSON original reste conservé.
- Les mesures au même timestamp mais avec un contenu différent restent distinctes :
  ce kit ne choisit pas arbitrairement une version « correcte ».
- Un listing OCI en échec ne marque pas les objets précédents comme disparus.
  Consulter bucket_scans et sync_runs : une couverture peut être ancienne.
- Une mesure sans timestamp, ou un timestamp avec fuseau sans timezone associée,
  invalide l'import du fichier entier : aucune sortie partielle silencieuse.
- Les valeurs biologiques proviennent du bucket biologique actuel. Les snapshots
  biologiques contextualisés restent dans records pour inspection.
- Contrôles qualité fournis : température/humidité absentes ou non numériques,
  humidité hors 0–100 %, présence du marqueur reconstruction. Ce ne sont pas des
  seuils médicaux, ni une validation complète de tous les capteurs.

## Limite : traitements WildTrace

sync_runs mesure les exécutions de CET importeur, pas les jobs WildTrace.
Les statuts de couverture sont des constats sur les sources, pas des diagnostics
certains d'échec. Pour voir durée, erreur et succès des traitements WildTrace,
il faut instrumenter leur code. Un contrat JSON est fourni dans
`pipeline-run.example.json` pour cette évolution ; il n'est pas encore ingéré.
Les logs existants ne sont pas analysés et aucun traitement n'est relancé.

## Exploitation et sauvegardes

```sh
docker compose logs --tail=100 metabase
docker compose --profile sync run --rm sync
docker compose exec -T postgres pg_dump -U wildtrace -d wildtrace -Fc > wildtrace.dump
docker compose exec -T postgres pg_dump -U wildtrace -d metabase -Fc > metabase.dump
docker compose stop
```

Les volumes persistent après stop et down. `docker compose down -v` SUPPRIME les
bases : ne pas l'utiliser pour un arrêt normal. Conserver les deux sauvegardes et .env
avant une mise à jour. Le schéma fourni s'initialise à chaque sync ; ce kit n'a pas
encore de système de migrations pour les futures évolutions.
L'image Metabase est latest par défaut : après validation de ton installation,
fixer METABASE_IMAGE dans .env à une version publiée pour maîtriser les mises à jour.
PostgreSQL est fixé à la version majeure 17.

L'interface est limitée à localhost et PostgreSQL n'expose pas de port hôte.
Ne pas publier les données biologiques ou GPS via les liens publics Metabase.
Le kit ne fournit pas d'hébergement distant ; en local il ne demande aucun abonnement.

## Vérification du kit

```sh
python3 -m unittest discover -s tests -v
```

Les tests utilisent des fixtures synthétiques pour les transformations, sans OCI.
Voir VALIDATION.md pour ce qui a réellement été vérifié lors de la préparation.

## Références

- https://github.com/eloiseLBC/WildTrace/blob/develop/src/utils/contextualizingUtils.py
- https://www.metabase.com/docs/latest/installation-and-operation/running-metabase-on-docker
- https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdkconfig.htm
