# Modèle quantitatif FX — Synthèse méthodologique
*Document de travail — v5, fourchette opérationnelle validée par test glissant réel sur une semaine FOMC ; tests de robustesse (COVID) et backtest complet en attente*

## 1. Objectif du projet

Construire un modèle quantitatif pour le marché du Forex (EUR/USD comme cas d'étude), avec une double ambition :

- **(a)** Mesurer de façon quantitative et testable statistiquement un déplacement comportemental du marché (peur/aversion au risque), plutôt que de le décrire qualitativement comme le fait une partie de la littérature de finance comportementale.
- **(b)** En tirer un usage opérationnel potentiel : signal d'aide à la décision (pas de prédiction certaine), et détection de régime de marché en temps réel.

**Révision du framing initial (b)** : l'objectif parlait initialement de régimes "normal / bulle / panique". Ce framing a été révisé lors de l'implémentation (voir `docs/regime_hmm.md`, section 1) : une bulle spéculative se caractérise typiquement par une phase de construction à volatilité *basse*, pas haute — un modèle de volatilité seul ne peut donc pas distinguer "marché calme normal" de "bulle en formation", les deux ayant la même signature de faible volatilité. Les régimes réellement détectés sont donc labellisés **"faible / normale / forte volatilité (stress-panique)"**, une distinction honnête sur ce que le modèle peut réellement mesurer.

**Avertissement méthodologique assumé** : le modèle n'a pas la prétention de prédire l'avenir avec certitude. L'objectif est d'aider à la prise de décision, pas de garantir un résultat.

**Note de cohérence linguistique** : ce document reste en français comme espace de réflexion de travail. Le README et le journal détaillé `docs/GARCH_1_1.md` sont rédigés en anglais, dans l'optique d'un portfolio et d'une candidature de master internationale — une traduction complète de ce document reste à faire si besoin.

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

**Statut : ΔY(t) est maintenant défini concrètement** — voir section 5. C'est le résidu standardisé du GARCH(1,1) à innovations Student's t, calibré sur les rendements log EUR/USD.

## 4. Choix de la variable Y (proxy de peur/volatilité)

### 4.1 Indices de référence écartés

- **CVIX (Deutsche Bank)** et **JPMorgan VXY Global** : produits propriétaires, accès Bloomberg/Refinitiv requis — hors de portée.
- **VIX actions (S&P 500) comme proxy** : écarté. Raisons :
  - Capture un risque spécifique aux actions US, potentiellement déconnecté du FX (signal contaminé, pas juste affaibli)
  - Chaîne de transmission VIX → FX indirecte et instable dans le temps (le signe de la corrélation change selon les périodes et le rôle du USD comme valeur refuge ou devise risquée)
  - Casse la cohérence de l'objet d'étude (mesurer un proxy d'un autre marché plutôt que le FX lui-même)

### 4.2 Solution retenue : volatilité conditionnelle FX construite en interne (GARCH)

Proxy retenu : résidu standardisé d'un modèle GARCH(1,1) calibré directement sur les rendements log EUR/USD — pas une simple fenêtre glissante d'écart-type (voir section 5.1 pour la clarification méthodologique sur ce choix). Justification générale : une mesure imparfaite mais bien ciblée (vol du bon marché) bat une mesure sophistiquée mais mal ciblée (vol d'un autre marché).

Limite assumée : capture la vol conditionnelle/réalisée, pas les anticipations (contrairement à une vol implicite type CVIX).

### 4.3 Choix de la transformation de Y

Quatre spécifications évaluées :
- (a) Différence simple ΔY(t) = Y(t) − Y(t−1) — écartée (poids économique non homogène selon le niveau de départ)
- (b) Variation relative (log-rendement) : ΔY(t) = ln(Y(t)/Y(t−1)) — retenue comme signal de **choc**
- (c) Écart à une moyenne mobile — signal de régime, pas de choc
- (d) Z-score standardisé — retenue comme signal de **régime**, input pour la détection de régime (HMM/Markov-switching)

Usage complémentaire retenu : (b) dans la régression sur r(t+1) à court terme ; (d) dans le futur modèle de détection de régime.

## 5. GARCH(1,1) — résumé (détail complet dans docs/GARCH_1_1.md)

### 5.1 Clarification méthodologique importante

La fenêtre glissante (approximation simple de la vol réalisée, évoquée initialement) et le GARCH ne sont **pas deux étapes séquentielles d'un même chemin**, mais deux approches concurrentes :

- **Chemin A — GARCH direct sur les rendements bruts** (retenu) : σ²(t) = ω + α·ε²(t−1) + β·σ²(t−1). Le modèle estime lui-même la vol conditionnelle et isole le choc par construction. Ne nécessite que des données journalières.
- **Chemin B — Volatilité réalisée rigoureuse (HAR-RV, Corsi 2009)** : nécessite des données intra-journalières haute fréquence, hors de portée avec l'accès aux données disponible.

**Décision confirmée** : chemin A (GARCH), compte tenu de l'accès aux données (clôtures journalières uniquement, voir section 6).

### 5.2 Résultat retenu : GARCH(1,1) à innovations Student's t

Deux spécifications testées (Normal vs Student's t) et comparées sur AIC/BIC, tests de Ljung-Box, ARCH-LM standardisé, et cohérence de la kurtosis empirique avec la kurtosis théorique implicite de ν.

**Modèle retenu : Student's t, ν ≈ 7,04** — nettement supérieur au modèle normal (ΔAIC ≈ 161,6, ΔBIC ≈ 155,2), diagnostics propres (pas d'effet ARCH résiduel), kurtosis empirique (1,831) cohérente avec la kurtosis théorique du ν estimé (1,973).

**Limite documentée** : la persistance (α+β) est sensible à l'hypothèse distributionnelle (0,9945 en Normal vs 0,9985 en Student's t), avec une demi-vie du choc estimée entre ~126 et ~462 jours selon la spécification — à traiter comme une fourchette, pas un chiffre unique, tant qu'un test de stabilité par sous-périodes n'a pas été fait.

Le résidu standardisé de ce modèle constitue la variable ΔY(t) opérationnelle du projet, sauvegardée dans `data/processed/eurusd_garch_shocks.csv`.

**Détail complet du processus** (pipeline de données, bugs rencontrés et corrigés, diagnostics complets, comparaison chiffrée) : voir [`docs/GARCH_1_1.md`](GARCH_1_1.md).

## 6. Sources de données retenues

- **FRED** (série DEXUSEU, `data_loader_fred.py`) — clôtures journalières, historique depuis 1999, source retenue après l'échec de `yfinance` sur le ticker EUR/USD (voir `docs/GARCH_1_1.md` section 2 pour le détail du problème rencontré)
- **ECB Statistical Data Warehouse** — taux de référence officiels, alternative/vérification possible
- OANDA (intraday) — non retenu à ce stade, le chemin GARCH ne requérant que du journalier

**Convention de prix retenue** : DEXUSEU = dollars par euro (convention de marché standard EUR/USD, EUR devise de base). L'exemple illustratif initial de ce document (section 2, tout début du projet) utilisait la convention inverse par erreur — corrigé ici pour la suite du projet.

## 7. Prochaines étapes

- [x] Spécifier le GARCH(1,1) sur les rendements log journaliers EUR/USD (librairie `arch`, Python) — fait, voir section 5 et `docs/GARCH_1_1.md`
- [x] Extraire le résidu standardisé (le "choc") de la vol conditionnelle estimée — fait
- [x] Estimer une régression simple r(t+1) = α + β₁·ΔY(t) + β₂·r(t) + u(t), sans variable de contrôle — fait, résultat nul (aucun coefficient significatif, R²=0.001), voir `docs/regression_baseline.md`
- [x] Formaliser les variables de contrôle (différentiel de taux, DXY, etc.) et les ajouter à la régression, en comparant β₁ avant/après leur ajout — fait, résultat robuste : β₁ quasi inchangé (-0,1329 → -0,1308), aucune variable significative, AIC/BIC se dégradent avec l'ajout des contrôles. Confirme, sans preuve de confusion, le résultat nul de la baseline. Voir `docs/control_regression.md`.
- [x] Tester si ΔY(t) explique la magnitude du rendement, |r(t+1)|, plutôt que sa direction — fait, résultat positif et robuste sur σ(t) en niveau (R²=0,090, p<0,001), mais nettement plus faible sur ΔY(t) (variation log, non significatif) — la transformation en variation dilue le signal par rapport au niveau. Résultat interprété comme validation de cohérence du GARCH, pas comme découverte nouvelle, et utilisable pour l'objectif (b) (fourchette de prix ajustée à la volatilité). Voir `docs/magnitude_regression.md`.
- [x] Aborder la détection de régime (HMM vs Markov-Switching GARCH) pour classer les régimes de volatilité — fait, via un HMM gaussien à 3 états sur log(σ(t)). Première tentative dégénérée (deux états quasi identiques, bascule quotidienne artificielle) diagnostiquée et corrigée par redémarrages multiples (8/10 convergent vers l'optimum global). Régimes finaux bien séparés et persistants (durées moyennes ~72 à ~127 jours selon le régime). Limite documentée : hérite de l'instabilité du GARCH global (voir ci-dessus) ; argument renforcé pour un futur Markov-Switching GARCH. Voir `docs/regime_hmm.md`.
- [x] Implémenter le Markov-Switching GARCH (K=2) — fait, via le package R `MSGARCH` (aucun équivalent Python mature, exception documentée et délibérée à la pile Python du projet). 2 régimes clairement séparés (σ long terme ≈0,21 vs ≈0,73), persistance plus faible en régime de stress qu'en régime calme (demi-vie ~64 vs ~237 jours — la panique s'estompe plus vite que le calme ne dure). AIC favorise le MS-GARCH, BIC favorise le GARCH simple — désaccord documenté, non tranché arbitrairement. Détection confirmée du choc COVID (probabilité de régime de stress : 9%→99,998% en 3 semaines). Voir `docs/ms_garch.md`.
- [x] Construire une fourchette de prix opérationnelle (objectif (b) initial) à partir de la prévision GARCH/MS-GARCH — fait, via `Risk()` (package `MSGARCH`) sur la distribution prédictive complète (mélange des 2 régimes, pondéré par leurs probabilités actuelles), pas une simulation de tirages (`predict()` ne renvoyait pas les tirages malgré l'argument demandé). Résultat au 2026-09-11 : fourchette à 95% = [1,1533 ; 1,1675] (largeur 1,22%), cohérente avec un quantile Student's t (ν≈7) vérifié indépendamment. Voir `docs/price_range.md`.
- [x] Corriger la base théorique du MS-GARCH — le package implémente Haas, Mittnik & Paolella (2004a), pas l'approximation de Gray (1996) comme documenté par erreur initialement. Conséquence : la vraie prévision conditionnelle par régime est calculable exactement (récursion indépendante par régime), pas juste approximable. Implémentée et validée par recoupement exact avec `Risk()` (0,3055 = 0,3055). Voir `docs/ms_garch.md` section 1 (corrigée) et `docs/price_range.md` section 4.
- [x] Fan charts multi-niveaux (20/50/80/95%) pour le mélange ET par régime — fait. Le ratio de largeur stress/calme n'est pas constant selon le niveau de confiance (2,09x à 20%, 1,88x à 95%), reflétant les formes de queue différentes (ν₁≈7 vs ν₂≈22). Voir `docs/price_range.md` section 8.
- [x] Test glissant en chaîne (11→14→15→16→17 septembre 2026, paramètres gelés) — fait. 3/4 dans la fourchette à 95% sur la clôture (mais 2/4 en tenant compte du plus bas intrajournalier) — résultat non concluant statistiquement (n=4), mais le seul dépassement net tombe exactement le jour de la décision Fed, cohérent avec la limite déjà documentée (le modèle ne peut pas anticiper un choc macro futur). Deux hypothèses non tranchées : réactivité lente du régime voulue (paramètres gelés) vs problème structurel — nécessite un test sur une vraie fenêtre de stress. Voir `docs/rolling_test.md`.
- [ ] Fan chart séquentiel pour le test glissant (visualiser les 4 fourchettes empilées dans le temps avec le prix réel)
- [ ] Test de robustesse sur une fenêtre de stress historique (ex. COVID février-avril 2020, mono-source FRED) — pour trancher entre les deux hypothèses de réactivité du régime
- [ ] Backtest complet (grand nombre de prévisions à 1 jour, taux de couverture empirique vs 95% nominal)

**Objectif (b) désormais complet** : signal d'aide à la décision (fourchette de prix réelle et calculée) et détection de régime en temps réel (HMM et MS-GARCH) sont tous deux livrés, documentés, et interprétés économiquement.
- [x] Tester la stabilité temporelle du GARCH par sous-périodes (limite identifiée en section 5.2) — fait, sur 5 sous-périodes égales (835 obs. chacune). Résultat : instabilité confirmée, la persistance (α+β) varie substantiellement selon la période (demi-vie ~65 à ~335 jours, hors artefact numérique d'une période proche de la frontière IGARCH). Renforce l'argument pour un Markov-Switching GARCH plutôt qu'un simple HMM à l'étape suivante. Voir `docs/garch_stability.md`.

**Note méthodologique sur l'ordre retenu** : la régression simple a précédé l'ajout des contrôles pour éviter un problème de confusion (évite d'attribuer à ΔY(t) un effet qui viendrait en réalité d'une variable corrélée). Entre magnitude et contrôles, l'ordre retenu est : contrôles d'abord (pour clore complètement la question de la direction avant de pivoter vers une nouvelle cible), magnitude ensuite, régime en dernier.

## 8. Exigence transversale : interprétation économique dans chaque journal

Chaque document détaillé (`GARCH_1_1.md`, `regression_baseline.md`, `control_regression.md`, `magnitude_regression.md`, `regime_hmm.md`) inclut désormais une section d'interprétation économique explicite — ce que les résultats signifient concrètement pour quelqu'un qui observe le marché, avec exemples chiffrés à l'appui (ex. probabilités de queue calculées pour illustrer l'importance des queues épaisses dans `GARCH_1_1.md`, taille d'effet économique des coefficients non significatifs dans `regression_baseline.md`/`control_regression.md`). Cette exigence a été ajoutée après coup à des documents déjà rédigés uniquement en termes statistiques — un référee doit pouvoir comprendre l'implication économique sans devoir traduire lui-même les coefficients et p-values.
