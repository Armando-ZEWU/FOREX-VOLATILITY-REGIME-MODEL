# Modèle quantitatif FX — Synthèse méthodologique
*Document de travail — v1, [date à mettre à jour à chaque révision]*

## 1. Objectif du projet

Construire un modèle quantitatif pour le marché du Forex (EUR/USD comme cas d'étude), avec une double ambition :

- **(a)** Mesurer de façon quantitative et testable statistiquement un déplacement comportemental du marché (peur/aversion au risque), plutôt que de le décrire qualitativement comme le fait une partie de la littérature de finance comportementale.
- **(b)** En tirer un usage opérationnel potentiel : signal d'aide à la décision (pas de prédiction certaine), et détection de régime de marché (normal / bulle / panique) en temps réel.

**Avertissement méthodologique assumé** : le modèle n'a pas la prétention de prédire l'avenir avec certitude. L'objectif est d'aider à la prise de décision, pas de garantir un résultat.

## 2. Point de départ théorique

Question fondatrice : P(t+1) dépend-il de P(t) ?

- Sur un marché aussi liquide que l'EUR/USD spot, la **direction** du prix suit approximativement une marche aléatoire (hypothèse de marché efficient, forme faible) — quasi imprévisible à partir du seul historique des prix.
- En revanche, la **magnitude/volatilité** du mouvement est partiellement prévisible, via le phénomène de clustering de volatilité (une période agitée tend à être suivie d'une période agitée).
- Conséquence opérationnelle : viser une **fourchette de prix** (intervalle de confiance basé sur la volatilité), pas un prix fixe.

## 3. Spécification du modèle — itérations

### 3.1 Équation initiale proposée

P(t+1) = X(t) + Y(t) + u(t)

où X = prix à l'instant t, Y = sentiment de peur du marché, u = erreur.

### 3.2 Corrections apportées

1. **Incohérence dimensionnelle** : impossible d'additionner un prix et un indice de peur sans coefficient. Nécessité d'un β : P(t+1) = P(t) + β·Y(t) + u(t).
2. **Non-stationnarité du niveau de prix** : les prix de change sont proches d'un processus à racine unitaire. Modéliser le niveau expose à une régression fallacieuse (Granger & Newbold, 1974). On modélise donc le **rendement log** :
   r(t+1) = ln(P(t+1)/P(t))
3. **Problème de simultanéité/causalité** : un indice de peur calculé à partir des prix d'options contemporains peut être une conséquence du prix, pas sa cause. Nécessité de décaler la variable explicative ou de tester la causalité de Granger.

### 3.3 Spécification retenue (version de travail)

r(t+1) = α + β₁·ΔY(t) + β₂·r(t) + Σγᵢ·Contrôlesᵢ(t) + u(t)

où ΔY(t) est la variation de la variable de peur/volatilité (pas son niveau), r(t) capture un éventuel momentum/mean-reversion résiduel, et les contrôles incluent différentiel de taux, corrélation avec DXY, etc. (à formaliser).

## 4. Choix de la variable Y (proxy de peur/volatilité)

### 4.1 Indices de référence écartés

- **CVIX (Deutsche Bank)** et **JPMorgan VXY Global** : produits propriétaires, accès Bloomberg/Refinitiv requis — hors de portée.
- **VIX actions (S&P 500) comme proxy** : écarté. Raisons :
  - Capture un risque spécifique aux actions US, potentiellement déconnecté du FX (signal contaminé, pas juste affaibli)
  - Chaîne de transmission VIX → FX indirecte et instable dans le temps (le signe de la corrélation change selon les périodes et le rôle du USD comme valeur refuge ou devise risquée)
  - Casse la cohérence de l'objet d'étude (mesurer un proxy d'un autre marché plutôt que le FX lui-même)

### 4.2 Solution retenue : volatilité réalisée FX construite en interne

Proxy : écart-type glissant des rendements log de EUR/USD (approximation initiale). Justification : une mesure imparfaite mais bien ciblée (vol du bon marché) bat une mesure sophistiquée mais mal ciblée (vol d'un autre marché).

Limite assumée : capture la vol passée/contemporaine, pas les anticipations (contrairement à une vol implicite).

### 4.3 Choix de la transformation de Y

Quatre spécifications évaluées :
- (a) Différence simple ΔY(t) = Y(t) − Y(t−1) — écartée (poids économique non homogène selon le niveau de départ)
- (b) Variation relative (log-rendement) : ΔY(t) = ln(Y(t)/Y(t−1)) — retenue comme signal de **choc**
- (c) Écart à une moyenne mobile — signal de régime, pas de choc
- (d) Z-score standardisé — retenue comme signal de **régime**, input pour la détection de régime (HMM/Markov-switching)

Usage complémentaire retenu : (b) dans la régression sur r(t+1) à court terme ; (d) dans le futur modèle de détection de régime.

## 5. Propriété statistique à traiter : autocorrélation mécanique de la volatilité

La volatilité réalisée est mécaniquement autocorrélée (clustering de volatilité) — une partie du "signal de peur" reflète l'inertie naturelle de la vol, pas un choc comportemental nouveau.

**Clarification méthodologique importante** : la fenêtre glissante (approximation simple de la vol réalisée) et le GARCH ne sont **pas deux étapes séquentielles d'un même chemin**, mais deux approches concurrentes :

- **Chemin A — GARCH direct sur les rendements bruts** : σ²(t) = ω + α·ε²(t−1) + β·σ²(t−1). Le modèle estime lui-même la vol conditionnelle et isole le choc (résidu standardisé) par construction. Ne nécessite que des données journalières.
- **Chemin B — Volatilité réalisée rigoureuse (HAR-RV, Corsi 2009)** : nécessite des données intra-journalières haute fréquence (rendements 5 minutes). Hors de portée sans accès à des données intraday de qualité.

**Décision prise** : chemin A (GARCH), compte tenu de l'accès aux données disponibles (voir section 6).

## 6. Sources de données retenues

- **Yahoo Finance** (`EURUSD=X`, librairie `yfinance`) — clôtures journalières, historique long, gratuit
- **FRED** (série DEXUSEU) — utile pour coupler avec données macro US
- **ECB Statistical Data Warehouse** — taux de référence officiels, historique depuis 1999
- OANDA (intraday) — non nécessaire à ce stade, écarté puisque le chemin GARCH ne requiert que du journalier

## 7. Prochaines étapes

- [ ] Spécifier le GARCH(1,1) sur les rendements log journaliers EUR/USD (librairie `arch`, Python)
- [ ] Extraire le résidu standardisé (le "choc") de la vol conditionnelle estimée
- [ ] Formaliser les variables de contrôle de la régression (différentiel de taux, DXY, etc.)
- [ ] Aborder la détection de régime (HMM vs Markov-Switching GARCH) pour classer normal/bulle/panique
- [ ] Mettre en place l'environnement Spyder + structure de dépôt GitHub
