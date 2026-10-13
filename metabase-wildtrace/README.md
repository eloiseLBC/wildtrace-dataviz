# Import des questions WildTrace dans Metabase

Ce kit crée une collection, 24 questions enregistrées et un dashboard dans ton
Metabase local. Il utilise l'API Metabase, pas un bouton d'upload de l'interface.
Python 3 suffit, sans installation de bibliothèques. Préparé pour l'API des versions
récentes, notamment la version v0.64.1.7 observée dans tes logs.

## 1. Vérifier le schéma

Le schema.sql enrichi joint doit être appliqué EN ENTIER. Il contient les nouvelles
colonnes city/country, stress_score, sleep_duration_score, temperature_value, etc.
Depuis le dossier wildtrace-dataviz après remplacement de sql/schema.sql :

```sh
docker compose exec -T postgres psql -U wildtrace -d wildtrace -v ON_ERROR_STOP=1 --single-transaction < sql/schema.sql
docker compose --profile sync build sync
```

Les données doivent déjà être importées. Metabase doit être accessible et la source
PostgreSQL WildTrace connectée. L'application du schéma ne remplit pas des buckets vides.

## 2. Importer

Décompresser ce kit, puis ouvrir un terminal dans le dossier contenant import_metabase.py
et questions.json. Lancer :

```sh
python3 import_metabase.py
```

Le script demande l'e-mail et le mot de passe de ton COMPTE METABASE.
Ce n'est ni le mot de passe POSTGRES_PASSWORD ni la clé OCI. La saisie du mot de passe
est masquée ; il n'est enregistré dans aucun fichier. La session est fermée à la fin.

Il sélectionne la source dont le nom affiché est wildtrace, sans tenir compte de la
casse. Si le nom est différent :

```sh
python3 import_metabase.py --database "WildTrace"
```

Si plusieurs bases ont le même nom, choisir leur identifiant affiché dans le message :

```sh
python3 import_metabase.py --database-id 2
```

L'identifiant 2 est un exemple, pas une valeur imposée.

Pour vérifier les requêtes sans créer les questions :

```sh
python3 import_metabase.py --check-only
```

Les vérifications exécutent LIMIT 0 : elles contrôlent la présence des vues et colonnes,
mais pas la pertinence des données ni le rendu visuel des graphiques.

## 3. Résultat

Le terminal affiche le lien du dashboard. La collection est nommée
« WildTrace — Dataviz », le dashboard « WildTrace — Suivi et qualité des données ».
Chaque graphique/question est éditable dans Metabase. Les courbes sont séparées par
unité (sommeil, HRV, température...) pour éviter de mélanger des échelles différentes.
Les questions utilisent tout l'historique importé ; aucun filtre global de période
n'est installé dans cette version. On peut modifier les SQL ou ajouter des filtres ensuite.

## Relancer sans doublons

Les éléments sont retrouvés par nom exact dans la collection dédiée. Les questions
existantes sont conservées, même si leur SQL ou leur apparence ont été modifiés.
Le script ajoute uniquement les questions manquantes au dashboard et conserve les
cartes déjà présentes. Ne pas renommer les éléments si tu souhaites qu'ils soient
retrouvés à la relance. Des éléments homonymes ambigus provoquent un arrêt.
Une erreur réseau au moment d'une création peut demander de vérifier la collection
avant relance ; le serveur peut avoir traité la requête sans que le client ait reçu sa réponse.

## Périmètre des données

- Jours calculés/contextualisés : dates distinctes, journée en cours exclue.
- Données manquantes : calendrier attendu depuis START_DAY.
- Stress : estimation existante, pas diagnostic.
- Moods/environnements : tags bruts déclarés ; pas de score d'humeur inventé.
- Classement du sommeil : pays avec au moins 3 nuits ayant un score disponible.
- sync_runs : exécutions de l'importeur, pas jobs de calcul WildTrace.
- Les valeurs ville/pays restent nulles si absentes de la source.
- Aucun partage public activé et aucune modification des données PostgreSQL par ce script.

## Validation réalisée

Compilation Python et validation du manifeste (24 noms uniques, SQL de lecture seule,
configuration des graphiques et disposition) effectuées. Le script n'a pas été exécuté
contre ton compte Metabase : l'authentification et la création réelles restent à valider.
En cas d'erreur, envoyer uniquement le message affiché, sans mot de passe.

## Références API

https://www.metabase.com/learn/metabase-basics/administration/administration-and-operation/metabase-api
Documentation de TON instance : http://localhost:3000/api/docs
Le dashboard utilise PUT /api/dashboard/{id} avec dashcards ; l'ancien endpoint
/api/dashboard/{id}/cards a été déprécié.

Ces fichiers sont livrés dans le ZIP, pas commités dans GitHub : l'intégration a refusé
l'écriture lors de la tentative précédente (HTTP 403).
