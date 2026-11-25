# Remédiation des secrets — Projet TaskFlow

## 1. Résultats des analyses

Deux analyses Gitleaks ont été réalisées.

### Analyse du répertoire actuel avant correction
- Règle : `generic-api-key`
- Fichier : `app/config.py`
- Ligne : 6
- Résultat : 1 secret détecté.

### Analyse de l'historique Git
- Nombre de commits analysés : 7
- Nombre de détections : 2
- Fichier `.env` : commit `e9d19246b9cd2ff846b7bb56c4c2a3970799205a`
- Fichier `app/config.py` : commit `a85c838c7b3721cae478659384d4f09b93e462bb`

Les deux détections correspondent à des expositions historiques de clés API.

## 2. Mesures correctives

- La clé codée en dur dans `app/config.py` a été retirée.
- La variable `PAYMENT_API_KEY` est désormais récupérée depuis l'environnement.
- Le fichier `.env` n'est pas présent dans le répertoire actuel.
- Aucun secret n'est ajouté à ce document.

## 3. Révocation simulée

Dans le cadre de ce TP, la révocation des deux clés exposées est considérée comme simulée.

Dans un environnement réel, chaque clé devrait être révoquée auprès du fournisseur du service concerné, puis remplacée par une nouvelle clé sécurisée.

## 4. Vérification après correction

Un nouveau scan Gitleaks du répertoire actuel a été effectué.

Résultat : aucune fuite détectée.

L'historique Git conserve les anciennes expositions. La suppression d'un secret du fichier actuel ne supprime pas automatiquement les anciennes versions présentes dans les commits.

## 5. Conclusion

La gestion des secrets a été améliorée : les clés ne sont plus stockées en dur dans le code et Gitleaks ne détecte plus de fuite dans le répertoire actuel.

Le scan de l'historique reste nécessaire pour identifier les anciennes expositions. La révocation effective des clés et, si nécessaire, le traitement de l'historique doivent être réalisés dans un environnement réel.