# FX Volatility Regime Model

> Modèle quantitatif exploratoire sur le marché des changes (EUR/USD), visant à mesurer un proxy de "peur"/volatilité du marché pour expliquer les rendements et détecter des régimes (normal / bulle / panique).

**Statut : projet de recherche en cours — étudiant en L3 économie internationale.**
Ce n'est pas un outil de trading en production. C'est un exercice de recherche appliquée en économétrie financière, pensé pour être honnête sur ses limites plutôt qu'impressionnant sur le papier.

## Pourquoi ce projet

[À rédiger : 2-3 phrases sur la question de recherche — pourquoi la volatilité/peur du marché FX t'intéresse, dans le prolongement de ton cursus en économie internationale / commerce international / économie monétaire internationale.]

## Question de recherche

Peut-on mesurer, de façon quantitative et testable statistiquement, un déplacement comportemental du marché des changes (aversion au risque / peur) — plutôt que de le décrire seulement qualitativement — et en tirer un signal d'aide à la décision, y compris une détection de régime de marché en temps réel ?

**Ce que ce modèle NE prétend PAS faire** : prédire la direction future des prix avec certitude. L'objectif est d'aider la prise de décision, pas de garantir un résultat — voir la section Limites.

## Méthodologie (résumé)

1. Modélisation des rendements log EUR/USD (pas les prix bruts, pour éviter la non-stationnarité)
2. Construction d'un proxy de volatilité/peur propre au marché FX, faute d'accès aux indices propriétaires (CVIX, JPMorgan VXY) — voir `docs/methodology.md` pour le raisonnement complet
3. Calibration d'un modèle GARCH(1,1) pour isoler le choc de volatilité de son inertie mécanique
4. [À compléter au fur et à mesure : régression, détection de régime HMM/Markov-switching]

Le raisonnement détaillé, y compris les choix écartés et pourquoi, est documenté dans [`docs/methodology.md`](docs/methodology.md).

## Structure du repo

```
fx-vol-regime-model/
├── data/
│   ├── raw/              # données brutes téléchargées, jamais modifiées
│   └── processed/        # rendements log, séries nettoyées
├── src/
│   ├── data_loader.py    # téléchargement/nettoyage des données
│   ├── features.py       # calcul rendements, transformations de la variable de volatilité
│   ├── garch_model.py    # calibration GARCH, extraction des chocs
│   └── regression.py     # spécification économétrique r(t+1) = ...
├── docs/
│   └── methodology.md    # journal méthodologique détaillé (décisions, corrections, raisonnement)
├── requirements.txt
└── README.md
```

## Sources de données

- [Yahoo Finance](https://finance.yahoo.com) (`EURUSD=X`, via `yfinance`) — clôtures journalières
- [FRED](https://fred.stlouisfed.org) (série DEXUSEU) — pour coupler avec des données macro US
- [ECB Statistical Data Warehouse](https://data.ecb.europa.eu) — taux de référence officiels

## Limites connues et assumées

- Le proxy de volatilité utilisé est une **volatilité réalisée/conditionnelle** (GARCH), pas une **volatilité implicite** — il ne capture pas les anticipations du marché, contrairement à un indice comme le CVIX (inaccessible sans accès Bloomberg/Refinitiv)
- Le lien de causalité entre volatilité et rendement futur reste à tester rigoureusement (risque de simultanéité)
- Le modèle est calibré sur données journalières uniquement, faute d'accès à des données intraday de qualité

## Reproduire

```bash
git clone [url]
cd fx-vol-regime-model
pip install -r requirements.txt
```

[Instructions d'exécution à compléter une fois les scripts écrits]

## Auteur

[Ton nom / pseudo GitHub] — étudiant en L3 Économie Internationale, FASEG, Université de Lomé.
