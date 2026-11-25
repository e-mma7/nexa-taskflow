# Note de triage SAST — Projet TaskFlow

## 1. Outil et périmètre

Outil utilisé : Semgrep

Configurations utilisées :
- `p/default`
- `p/python`
- Règle personnalisée : `audit/semgrep-custom.yml`

Périmètre : dossier `app/` du projet TaskFlow.

## 2. Analyse initiale

Le premier scan a remonté 12 findings, correspondant à plusieurs problèmes de sécurité.

| Problème | Résultat du triage | Mesure corrective |
|---|---|---|
| Construction SQL par concaténation | Vrai positif | Requête SQL paramétrée |
| Utilisation de MD5 | Vrai positif | Remplacement par `generate_password_hash` |
| `subprocess` avec `shell=True` | Vrai positif | Suppression de l'appel shell et liste blanche des formats |
| Désérialisation avec `pickle.loads` | Vrai positif | Remplacement par une lecture JSON contrôlée |
| Écoute sur `0.0.0.0` | Alerte contextuelle pertinente | Passage à `127.0.0.1` |
| `debug=True` | Vrai positif en configuration de déploiement | Passage à `debug=False` |

Les alertes multiples sur certaines lignes correspondent à des règles différentes détectant le même problème. Elles ne représentent donc pas nécessairement des vulnérabilités indépendantes.

## 3. Corrections complémentaires

Lors du scan de validation, Semgrep a également détecté un retour direct de chaîne formatée dans la route `/export`, avec un risque potentiel de XSS.

La réponse a été remplacée par une réponse JSON avec `jsonify()`.

## 4. Règle personnalisée

Une règle spécifique au projet a été créée :

- Identifiant : `taskflow-subprocess-shell-true`
- Langage : Python
- Sévérité : ERROR
- Risque : CWE-78, injection de commande

La règle a été validée avec `semgrep --validate`, puis testée sur un fichier temporaire contenant volontairement une utilisation dangereuse de `subprocess` avec `shell=True`.

Résultat : la règle a détecté le problème. Le fichier de test a ensuite été supprimé.

## 5. Faux positifs et exceptions

Aucun faux positif confirmé n'a été retenu dans le triage.

Les alertes qui se chevauchaient ont été regroupées lorsqu'elles signalaient le même problème.

Aucune exception ni suppression de règle Semgrep n'a été ajoutée.

## 6. Résultat final

Après correction, le scan de validation a donné :

- 321 règles exécutées
- 3 fichiers analysés
- 0 finding
- 0 finding bloquant

Les tests automatisés ont également réussi : 3 tests passés.

## 7. Conclusion

Les vulnérabilités identifiées ont été corrigées et une règle personnalisée permet de détecter la réintroduction d'une injection de commande.

Le contrôle Semgrep est intégré au pipeline GitHub Actions avec l'option `--error`, afin de rendre les findings bloquants.