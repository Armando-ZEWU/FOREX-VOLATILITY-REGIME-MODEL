# Markov-Switching GARCH (K=2)

*Companion document to `methodology.md`, `docs/GARCH_1_1.md`,
`docs/garch_stability.md`, and `docs/regime_hmm.md`. This document covers
the project's final planned model: a Markov-Switching GARCH that
re-estimates ω, α, β separately per regime. It is motivated by the
sub-period variation in persistence reported in `garch_stability.md`
(variation in point estimates; the formal likelihood-ratio test in that
document does not establish an instability, p = 0.277) and addresses that
variation more directly than the
HMM-on-top-of-a-fixed-GARCH approach in `regime_hmm.md`.*

## 1. Why R, not Python — a documented, deliberate exception

Every other stage of this project was implemented in Python (`arch` for
GARCH, `hmmlearn` for the HMM). Markov-Switching GARCH is different: no
comparably mature Python package exists. The standard reference
implementation is the R package **MSGARCH** (Ardia, Bluteau, Boudt,
Catania, Trottier, 2019, *Journal of Statistical Software*), built in
C++/Rcpp.

This is not merely a tooling gap. True MS-GARCH estimation faces a
genuine theoretical difficulty, documented since Hamilton & Susmel
(1994): in the fully general model, the conditional variance in a given
regime depends, in principle, on the entire history of regime paths
since the start of the series (because σ²(t) depends on σ²(t−1), which
itself depended on whichever regime was active at t−1, and so on) —
making the exact likelihood of that fully general model computationally
intractable beyond a handful of observations, since it requires summing
over an exponentially growing number of regime paths.

Two different responses to this exist in the literature. Gray (1996)
keeps the fully general model and makes it *tractable by approximating
it*: at each step, the K regime-conditional variances are collapsed into
a single expected variance (weighted by the filtered regime
probabilities), used as the common lagged-variance input going forward —
a genuine approximation to the fully general model's likelihood.

MSGARCH does not do this. It implements the specification of Haas,
Mittnik & Paolella (2004a), which *sidesteps* the path-dependency problem
instead of approximating around it: each regime k runs its own
self-contained GARCH(1,1) recursion (σ²_k(t) = ω_k + α_k·r(t−1)² +
β_k·σ²_k(t−1)), fed by the same observed return but its own lagged
variance — no cross-regime collapsing at any step. The observed return's
density is then the K-regime mixture of these K parallel processes,
weighted by the regime probabilities. This gives an *exact* likelihood
for this (more restricted) model — it is not an approximation in Gray's
sense. The real cost is different: each regime's path ignores the
history of which regime was *actually* realized at each past date, a
simplification relative to the fully general model, but not the same
kind of approximation as Gray's collapsing.
Given this, and that the person running this project has R available,
this stage was run as a **single, deliberate, documented exception** to
the project's otherwise all-Python pipeline: an R script (`ms_garch.R`)
run directly (not via `rpy2`, to avoid Python-R bridging overhead for a
one-off analysis), producing CSV outputs reloaded into the Python-based
project for any further work.

## 2. Choice of K=2, not K=3

The HMM in `regime_hmm.md` used 3 states (low/normal/high volatility).
This stage deliberately uses **K=2**, not 3, for a stated reason, not
arbitrarily: MS-GARCH estimation is substantially harder numerically than
fitting a Gaussian HMM on an already-computed scalar series (σ(t)) — it
must jointly estimate ω, α, β **per regime**, plus the transition matrix,
under the Haas et al. (2004a) parallel-regime specification described above. Each additional
regime multiplies this difficulty. The FX/equity MS-GARCH literature
(e.g. Klaassen, 2002; Marcucci, 2005) commonly starts with 2 regimes
before considering more. This is a genuine methodological difference from
the HMM, not an inconsistency — the two tools face different numerical
constraints.

## 3. Specification and errors encountered

### 3.1 Model specification

2 regimes, each a GARCH(1,1) ("sGARCH") with Student's t innovations
("std") — matching the single-regime specification already validated in
`GARCH_1_1.md`, with one difference: no mean equation is estimated here
(returns are treated as zero-mean), whereas the single-regime `arch` fit
estimates a constant mean μ. The parameter counts in section 5 reflect
this.

### 3.2 First error: conflicting specification arguments

```
Error in CreateSpec(...): you can only use the variable K if you specified
one regime in variance.spec and distribution.spec
```

The first version of the script passed both a length-2 vector in
`variance.spec`/`distribution.spec` AND `K = 2` in `switch.spec` — two
alternative ways of specifying the number of regimes that `CreateSpec()`
does not allow combined. **Fix**: specify a single regime
(`model = c("sGARCH")`, `distribution = c("std")`) and let `K = 2` expand
it automatically.

### 3.3 Second error: row-count mismatch when saving regime probabilities

```
Error: arguments imply differing number of rows: 4175, 4176
```

`State()`'s `SmoothProb` output has **T+1** rows, not T, confirmed via the
package documentation: row 1 represents the pre-sample prior (t=0, before
any observation is seen), and rows 2 to T+1 correspond to the actual T
observed trading days. `FiltProb`, by contrast, has exactly T rows. This
was not guessed — the discrepancy was diagnosed by printing the object's
structure (`str()`) before trusting any extraction, and confirmed against
the official package documentation before applying the fix. **Fix**:
drop the first row of `SmoothProb` (index 1, the t=0 prior), not the last,
when aligning with the project's T=4175 dates.

## 4. Results

### 4.1 Fitted parameters

```
             Estimate   Std.Error    t value      Pr(>|t|)
alpha0_1   0.0001241    0.0002112    0.587        0.278   (omega, regime 1)
alpha1_1   0.0106220    0.0077169    1.376        0.084   (alpha, regime 1)
beta_1     0.9864591    0.0013367  737.970        <1e-16  (beta, regime 1)
nu_1       7.0711       0.9083       7.785        <1e-14  (regime 1)
alpha0_2   0.0057432    0.0039894    1.440        0.075   (omega, regime 2)
alpha1_2   0.0090000    0.0132647    0.678        0.249   (alpha, regime 2)
beta_2     0.9802132    0.0083909  116.818        <1e-16  (beta, regime 2)
nu_2      22.0046      16.8510       1.306        0.096   (regime 2, imprecise)
P_1_1      0.99753      0.00311    320.741        <1e-16  (stay in regime 1)
P_2_1      0.00627      0.00130      4.809        <1e-6   (regime 2 -> regime 1)

LL: -2806.64   AIC: 5633.27   BIC: 5696.64
Stable probabilities: Regime 1 = 71.7%, Regime 2 = 28.3%
```

The model has 10 free parameters (four per regime, plus the two free
transition probabilities). The two remaining entries of the transition
matrix follow from the rows summing to 1; the full matrix (as saved in
`ms_garch_transition_matrix.csv`) is:

| From \ To | Regime 1 | Regime 2 |
|---|---|---|
| Regime 1 | 0.99753 | 0.00247 |
| Regime 2 | 0.00627 | **0.99373** |

### 4.2 Which regime is "high volatility"?

Long-run (unconditional) variance per regime, ω/(1−α−β):

| Regime | α+β | Half-life (within-regime GARCH persistence) | Long-run σ implied by the parameters |
|---|---|---|---|
| 1 | 0.9971 | 237.1 days | 0.206 |
| 2 | 0.9892 | 63.9 days | 0.730 |

**Regime 2 is the high-volatility regime**, occurring 28.3% of the time:
on the days where its smoothed probability exceeds 50% (1,080 days), the
realized daily standard deviation of returns is 0.70, against 0.44 on the
remaining 3,095 days — a ratio of 1.6 (the classification is itself based
on volatility, so this is an indicative ratio, not an independent test).
The long-run σ implied by the parameters (0.73 vs. 0.21, a ratio of 3.5)
is a much larger and much less precise figure: ω is not significant in
either regime (p = 0.278 and 0.075) and α+β is close to 1, so the
denominator 1−α−β is small (0.0029 and 0.0108) and poorly determined. It
should not be read as a measure of realized volatility.

The HMM in `regime_hmm.md` has
three states, so its "high volatility" state (32.9% of the time) and this
model's regime 2 do not partition the sample in the same way: the
closeness of 32.9% and 28.3% should be read as an order-of-magnitude
consistency, not as independent confirmation.

### 4.3 A counter-intuitive finding — suggestive, not established

In the point estimates, the high-volatility regime has **lower** GARCH
persistence (α+β = 0.989, 63.9-day half-life) than the low-volatility
regime (α+β = 0.997, 237.1-day half-life). In plain terms, the point
estimates say that **acute stress fades faster than calm periods last**.

This should be read as suggestive, not as an established result. The
difference in α+β is 0.0079. Using the standard errors of section 4.1 and
ignoring the covariance between α and β within each regime (which is not
saved with the estimates), the standard error of that difference is about
0.018, i.e. t ≈ 0.45. The covariances would refine this figure, but
nothing here supports a statistically significant difference. In
addition, a half-life ln(0.5)/ln(α+β) is extremely sensitive when α+β is
this close to 1 (see the Period 2 diagnosis in `garch_stability.md`,
section 4).

If the difference is real, it makes economic sense — a crisis shock
(e.g. a central bank surprise, a liquidity panic) is intense but tends to
resolve within a few months, whereas a calm regime, once established, can
persist for the better part of a year before the next disruption.

**Important distinction, easy to conflate**: this within-regime half-life
(how fast GARCH shocks decay *inside* a regime) is a different concept
from the Markov chain's own regime duration (how long the market *stays*
in a given regime before switching). Using 1/(1−P) with the transition
matrix of section 4.1, the Markov-implied expected regime durations
(in trading days, as the data are daily trading observations) are:

- Regime 1 (low vol): 1/(1−0.99753) ≈ **404 trading days**
- Regime 2 (high vol): 1/(1−0.99373) ≈ **160 trading days**

Both regime *durations* are longer than their respective *within-regime
half-lives* — expected, since a regime can persist long after most of a
given shock's direct effect has already decayed within it.

### 4.4 Regime 2's tail parameter (ν₂ = 22) is imprecisely estimated

ν₂ = 22.0 (p = 0.096, not significant at 5%) is far higher than regime 1's
ν₁ = 7.07 (highly significant) — implying near-Gaussian tails in the
high-volatility regime, versus fat tails in the low-volatility regime.
This is plausible (the regime split may itself be absorbing some of the
extreme events that drove the single-regime model's fat tails, similar to
the mechanism discussed for the HMM's Gaussian emissions in
`regime_hmm.md` section 5) but the large standard error (16.85) means this
specific estimate should not be treated as precise — likely a consequence
of Regime 2 containing a smaller number of observations (~28% of 4,175 ≈
1,183 days) than Regime 1, reducing the precision with which a shape
parameter like ν can be pinned down.

A naive 95% Wald interval (ν₂ ± 1.96 × SE = 22.0 ± 1.96 × 16.85) would
give approximately [−11, 55], but this interval is not meaningful here: ν
is a bounded parameter (it must exceed 2 for the variance to exist), and
the Wald construction — symmetric around the point estimate, assuming
approximate normality — respects neither that boundary nor the typically
skewed sampling distribution near it. The negative lower bound should
never be quoted or interpreted. A proper interval would require a
likelihood-profile approach, not attempted here. The practical consequence
is unchanged: this estimate should not be treated as precise.

## 5. Comparison with the single-regime GARCH (`GARCH_1_1.md`)

| | Single-regime (Student's t) | MS-GARCH (K=2) |
|---|---|---|
| Free parameters | 5 (μ, ω, α, β, ν) | 10 |
| Log-likelihood | -2818.39 | -2806.64 (+11.75) |
| AIC | 5646.78 | **5633.27** (-13.51, favors MS-GARCH) |
| BIC | 5678.46 | 5696.64 (**+18.18, favors single-regime**) |

**AIC and BIC disagree** — a common and expected outcome when comparing a
regime-switching model to its single-regime counterpart: AIC penalizes
extra parameters less severely than BIC, and MS-GARCH adds 5 parameters
over the single-regime model (10 vs. 5; the single-regime fit estimates a
constant mean that the MS-GARCH specification does not, so the two models
also differ in their mean specification). This is reported plainly as a
genuine ambiguity, not resolved in favor of either model — the honest
conclusion is that **the added complexity of MS-GARCH buys a real but
modest improvement in fit, at a parameter cost that BIC judges as not
worthwhile, while AIC judges as worthwhile**. Neither criterion is
"more correct" in general; this is a known, unresolved tension in model
selection between AIC (better for prediction-oriented use) and BIC (better
for parsimony/true-model-identification-oriented use).

## 6. Case study: does the model detect the COVID-19 shock? (March 2020)

This check was run specifically because a first look at regime
classifications by year (using the Viterbi path, the single most likely
regime per day; see the provenance note in section 8) showed 2020 spending
only 36 out of 250 trading days
(≈14%) in the high-volatility regime — surprisingly low compared to
2010 (100% of days) and 2011 (81-84%), Eurozone debt crisis years, and
2022 (80-84%). (The ranges reflect the two classification rules: the
Viterbi path, and a 50% cutoff on the smoothed probabilities saved in
`ms_garch_regime_probs.csv`. 2012, sometimes grouped with the crisis
years, is at 0% under both rules.) This was investigated rather than
assumed to be either a genuine economic finding or a model flaw.

### 6.1 What the smoothed probabilities actually show

Examining the smoothed probability of the high-volatility regime day by
day around the shock:

| Date | P(high-vol regime) |
|---|---|
| 2020-02-18 | 9.2% |
| 2020-02-25 | 56.8% |
| 2020-02-26 | 91.5% |
| 2020-02-28 | 99.4% |
| 2020-03-11 | **99.998%** |
| 2020-03-19 | 98.4% |
| 2020-04-01 | 77.6% |
| 2020-04-17 | 25.4% |
| 2020-04-30 | 14.9% |

**In hindsight, the model identifies the shock clearly and quickly** —
the probability rises from 9% to over 99% in about three weeks (Feb 18 –
Mar 11), exactly tracking the real-world COVID market panic, then decays
back down over the following six weeks.

**These are smoothed probabilities, not a real-time signal.** The value
shown for a given day uses observations up to the end of the sample,
including the days that followed. The table describes *when* the regime
shifted, not what a user would have known on that day. The real-time
behaviour is measured in `covid_robustness_test.md`, with a model
estimated on pre-2020 data only: the predicted probability of the stress
regime at forecast time was 0.3% on 21 and 27 February, 2.5% on 2 March,
49.3% on 6 March and 98.7% on 12 March. That is a different model and a
different quantity (predicted, not smoothed), so the two series are not
strictly comparable, but a lag of roughly one to two weeks relative to the
smoothed trajectory above is the relevant order of magnitude for an
operational user.

### 6.2 Why the annual Viterbi count was misleading

The Viterbi path only records which regime has the *higher* probability
on a given day (a binary >50% cutoff), collapsing a smooth, informative
probability trajectory into a coarse yes/no label. The elevated-probability
window here (Feb 25 – Apr 9, 33 consecutive trading days above 50%) is
close to the 36-day count found — the annual tally was not
wrong, but it **discards the shape of the transition**: a genuinely fast,
extreme spike (9% → 99.998% in three weeks) looks statistically identical
in a simple day-count to a slower, weaker one that happens to cross 50%
for a similar number of days. **Lesson for interpretation, documented
here rather than left implicit**: comparing regimes by day-count per year
is too coarse a measure to judge relative shock intensity; the smoothed
probability trajectory (peak level, speed of transition) is the
economically meaningful signal, and the Viterbi/day-count view should be
treated as a simplification, not a substitute for it.

## 7. Economic interpretation — what this means for someone watching the market

Bringing sections 4-6 together into plain economic terms:

- EUR/USD alternates between two distinct volatility regimes: a **calm
  regime** (realized daily volatility ≈ 0.44 on the days it dominates,
  occurring ~72% of the time, lasting on average about 404 trading days,
  i.e. roughly 1.6 years, once entered) and a **stress regime** (≈ 0.70 on
  the days it dominates — about 1.6x as volatile — occurring ~28% of the
  time, lasting on average about 160 trading days, i.e. roughly 7-8
  months). The model-implied long-run σ (0.21 vs. 0.73) exaggerates this
  gap and is imprecise (section 4.2).
- In the point estimates, the intensity of shocks within a stress regime
  fades **faster** (half-life ~64 days) than within a calm regime
  (~237 days) — stress would be sharp but comparatively short-lived at
  the shock level, even though the *regime itself* (the Markov state) can
  still take months to fully resolve. This difference is not
  statistically established (section 4.3) and should be read as
  suggestive.
- In hindsight, the model places the real, sudden crisis (COVID, March
  2020) within about three weeks, moving from near-certainty of "calm" to
  near-certainty of "stress". That is a retrospective description of when
  the regime shifted; as an operational early-warning signal it lagged by
  roughly one to two weeks in the out-of-sample test (section 6.1).
- Compared to a single, undifferentiated GARCH (`GARCH_1_1.md`), this
  model offers a genuinely different, regime-aware description of
  volatility: it explicitly answers "which of two regimes are we in",
  rather than averaging both regimes' dynamics into one fixed set of
  parameters. Note that the formal test in `garch_stability.md` did **not**
  establish that the single-regime model's parameters are statistically
  unstable across time (likelihood-ratio test, p = 0.277): the motivation
  for MS-GARCH rests more defensibly on its being the theoretically
  appropriate tool for regime-dependent dynamics and on its AIC advantage
  (section 5) than on a proven instability of the simpler model — at the
  acknowledged cost of a heavier, harder-to-estimate model whose benefit
  AIC judges worthwhile and BIC does not.

## 8. Known limitations

- MSGARCH's likelihood is exact for the (more restricted) Haas et al. (2004a) specification it implements — it is not an approximation of that model. What remains genuinely intractable is the fully general path-dependent MS-GARCH likelihood (section 1); MSGARCH avoids that intractability by using a different, deliberately more restricted model, not by approximating the general one.
- ν₂ (regime 2's tail parameter) is imprecisely estimated (section 4.4);
  should not be over-interpreted on its own.
- The difference in persistence between the two regimes (section 4.3) is
  not tested; the half-lives are point estimates, sensitive to α+β near 1.
- The long-run σ figures implied by the parameters (0.206 and 0.730) rest
  on ω, which is not significant in either regime, and on a denominator
  1−α−β close to zero: they are imprecise, and their ratio (3.5) is well
  above the ratio of realized volatilities on the days each regime
  dominates (1.6) (section 4.2).
- AIC and BIC disagree on whether the added complexity is justified
  (section 5) — this project does not adjudicate between the two criteria,
  reporting the disagreement instead of picking a side to force a clean
  narrative. The two models also differ in their mean specification
  (constant mean estimated in the single-regime fit, none here).
- The regime probabilities analysed in section 6 are smoothed (ex post).
  A real-time user would rely on filtered or predicted probabilities,
  which react later (section 6.1).
- **The Viterbi path used in section 6 is not produced by any script
  currently in the project.** `ms_garch.R` as written exports only the
  smoothed regime probabilities (`ms_garch_regime_probs.csv`) from the
  `State()` output; the Viterbi classification behind the opening
  paragraph and the year-by-year day counts of section 6 was generated in
  an interactive session and not captured in a saved script. Anyone
  reproducing this analysis from the repository alone would need to add an
  extraction of the Viterbi path from the `State()` output
  (`state_probs_obj` in `ms_garch.R`) themselves — not yet done.
- K=2 was not compared against K=3 at this stage (see section 2's
  rationale for starting at 2); a natural extension, not yet undertaken.
- This stage depends on R and the MSGARCH package — a deliberate,
  documented exception to the rest of the project's Python pipeline
  (section 1), which means it cannot be re-run purely from the Python
  codebase without R installed alongside it.

## 9. Files produced at this stage

- `src/ms_garch.R` — model specification, ML fitting, per-regime parameter
  extraction, transition matrix, smoothed regime probability export, and
  export of the plain numeric estimates
- `data/processed/ms_garch_transition_matrix.csv`
- `data/processed/ms_garch_regime_probs.csv` — per-day smoothed
  probabilities for both regimes, aligned with EUR/USD trading dates
- `data/processed/ms_garch_par.rds` — plain numeric estimates only
  (`par`, `loglik`, `MatCoef`), used by `ms_garch_forecast.R` and the
  downstream forecasting scripts (see `price_range.md`); the fit object
  itself is deliberately not saved, because its Rcpp external pointer
  becomes invalid after reloading
