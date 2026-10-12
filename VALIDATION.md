# Validation effectuée

- 8 tests unitaires réussis : conversion en date locale, timestamps historiques,
  cohérence des journées contextualisées, rejet des entrées invalides et vides,
  empreintes stables et gestion d'un fuseau manquant.
- Compilation Python réussie pour importer.py, model.py et configure.py.
- `docker compose config --quiet` réussi avec une configuration générée.
- Aucun accès aux buckets réels ; aucune clé ou donnée personnelle dans l'archive.
- Docker Engine n'était pas démarré : installation des dépendances, schéma SQL,
  transactions PostgreSQL, Metabase et import OCI non testés de bout en bout.

Le kit est une première version autonome à configurer et valider localement.
Le dashboard se compose dans Metabase avec les requêtes SQL incluses.
