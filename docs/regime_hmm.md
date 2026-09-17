# Regime Detection via Gaussian HMM

*Companion document to `methodology.md` (objective (b)), `docs/GARCH_1_1.md`,
and `docs/garch_stability.md` (whose instability finding is a documented
limitation inherited here). This document covers the full experiment: the
conceptual framing decided before coding, a first run that produced a
degenerate/unusable fit, the diagnosis and fix, the final validated
results, and open questions raised along the way.*

## 1. Objective and conceptual framing decided before coding

The project's opening objective (b), stated at the very start of this
work, was to detect market regimes described as "normal / bubble / panic."
Before implementing anything, this framing was revisited and revised.

### 1.1 Why "bubble" is not an accurate label for what this model detects

A financial bubble's build-up phase is often characterized by **low,
stable** volatility — steady, unremarkable price appreciation is part of
what makes a bubble look "safe" and attracts more capital. It is typically
the **burst**, not the bubble itself, that produces a spike in volatility.
A volatility-only model (this HMM, or the GARCH underlying it) has no way
to distinguish "ordinary calm market" from "bubble quietly inflating" —
both present an identical low-volatility signature. Labeling a detected
low-volatility state as "no bubble" and a high-volatility state as
"bubble" would be an unsupported conflation of two different economic
concepts: a volatility regime (directly measurable here) and a valuation
regime (would require a measure of price deviation from fundamentals,
outside this project's scope).

**Decision**: states are labeled by what the model actually measures —
**"low volatility" / "normal volatility" / "high volatility
(stress/panic)"** — not "normal / bubble / panic". This revises the
original framing in `methodology.md`'s objective (b) for accuracy, rather
than assuming the original wording was correct once implementation forced
the question.

## 2. Input variable and transformation

**Input**: σ(t), the GARCH(1,1) conditional volatility (Student's t
specification, from `GARCH_1_1.md`) — the level, not its variation ΔY(t),
consistent with the finding in `magnitude_regression.md` that the level
carries substantially more explanatory information than the log-change.

**Transformation applied**: log(σ(t)), not σ(t) raw. This is a **level**
transformation (monotonic, preserves ordering) — not to be confused with
ΔY(t) = ln(σ(t)/σ(t−1)), which is a **variation** (a genuinely different
quantity). The log transform was applied because `GaussianHMM` assumes
each hidden state generates approximately normally-distributed
observations; σ(t) is strictly positive and likely right-skewed in its raw
form, a poor fit for that assumption — the same reasoning already applied
when the project moved from raw EUR/USD prices to log returns
(`methodology.md`, section 3.2).

## 3. First attempt — a degenerate, unusable fit

### 3.1 What went wrong

A first `GaussianHMM(n_components=3)` fit, with a single random
initialization, produced:

```
State 0 (low volatility):    mean(log sigma) = -0.9306, std = 0.1752, freq = 28.6%
State 1 (normal volatility): mean(log sigma) = -0.9304, std = 0.1753, freq = 28.6%
State 2 (high volatility):   mean(log sigma) = -0.4444, std = 0.1396, freq = 42.9%
```

States 0 and 1 are statistically indistinguishable (mean difference of
0.0002 — numerical noise, not a real distinction). The last 10 days of
output showed the model alternating between state 0 and state 1 on
**every single day** (0, 1, 0, 1, 0, 1, ...) — the opposite of the
persistence a genuine volatility regime should show.

### 3.2 Diagnosis

Two contributing factors, both worth recording:

1. **EM local optimum**: the Expectation-Maximization algorithm used to
   fit HMMs can converge to different solutions depending on random
   initialization; a single run risks landing on a poor local optimum,
   here one that split a single real regime into two near-duplicate
   states.
2. **A structural risk specific to this series**: σ(t) from a highly
   persistent GARCH (β ≈ 0.96, per `GARCH_1_1.md`) is an extremely smooth,
   near-continuous trend. A discrete-state Gaussian HMM assumes each state
   produces i.i.d. noise around a fixed mean; a smoothly drifting series
   with little true idiosyncratic noise is a harder case for this
   assumption, and can tempt the EM algorithm toward artificially slicing
   a continuum into oscillating pseudo-states rather than finding genuine
   discrete regimes. This risk was flagged explicitly before re-running,
   as a possible sign that the specification itself (not just the
   initialization) could be at fault.

### 3.3 Fix applied

`fit_regime_hmm` was rewritten to try 10 random initializations
(`random_state` 0 through 9) and retain the fit with the highest
log-likelihood among converged runs, plus an automatic check that warns if
any two states end up with near-identical means (< 0.05 apart on the log
scale) — so a degenerate fit like the first attempt could never again pass
silently as a valid result.

## 4. Final, validated results

### 4.1 Convergence check

```
Restart 0: converged=True, log-likelihood=-745.41
Restart 1: converged=True, log-likelihood=1665.67
Restart 2: converged=True, log-likelihood=3302.55
Restart 3: converged=True, log-likelihood=3302.55
Restart 4: converged=True, log-likelihood=3302.55
Restart 5: converged=True, log-likelihood=3302.55
Restart 6: converged=True, log-likelihood=3302.55
Restart 7: converged=True, log-likelihood=3302.55
Restart 8: converged=True, log-likelihood=3302.55
Restart 9: converged=True, log-likelihood=3302.55

10/10 restarts converged. Best log-likelihood: 3302.55
```

8 of 10 restarts converge to the identical log-likelihood (3302.55) —
strong evidence this is the **global optimum**, not another local one.
This resolved the section 3 problem: it was primarily an initialization
issue, not a fundamental unsuitability of a Gaussian HMM for this series
(the structural concern in section 3.2 remains worth keeping in mind for
future extensions, but did not materialize as a blocking problem here).

### 4.2 Regime summary

| State | Label | Mean(log σ) | Std | Frequency | Approx. σ level |
|---|---|---|---|---|---|
| 0 | Low volatility | -1.0725 | 0.1268 | 29.0% | 0.342 |
| 1 | Normal volatility | -0.7476 | 0.0885 | 38.1% | 0.474 |
| 2 | High volatility (stress/panic) | -0.3907 | 0.1081 | 32.9% | 0.677 |

The three states are now clearly separated (means -1.07 / -0.75 / -0.39,
non-overlapping given their standard deviations), unlike the degenerate
first attempt.

### 4.3 Transition matrix and implied regime persistence

```
                          to low    to normal   to high
from low volatility       0.9921      ...        0.0000
from normal volatility    0.0067      ...        0.0072
from high volatility      0.0000      ...        0.9910
```

The diagonal (staying in the same regime) is very high for the low and
high volatility states (0.9921 and 0.9910), consistent with genuine
persistence rather than day-to-day noise. Using the standard formula for
expected regime duration, 1 / (1 − p_stay):

- **Low volatility**: 1 / (1 − 0.9921) ≈ **127 trading days** (~6 months)
- **High volatility (stress/panic)**: 1 / (1 − 0.9910) ≈ **111 trading days** (~5 months)
- **Normal volatility** (p_stay ≈ 1 − 0.0067 − 0.0072 ≈ 0.9861, from the
  "from normal" row): 1 / (1 − 0.9861) ≈ **72 trading days** (~3.5 months)

These durations are of the same order of magnitude as some of the
half-lives found in `garch_stability.md` (e.g. Periods 1, 4, 5 in the
65-80 day range) — a rough but sensible consistency check between the two
independent analyses, though not a formal validation.

### 4.4 Most recent observations

The last 10 trading days in the sample (2026-08-28 to 2026-09-11) are all
classified as "low volatility" — a stable, single-regime stretch, not an
artificial daily flip as in the first (degenerate) attempt.

## 5. Why Gaussian emissions here, despite Student's t being preferred for the GARCH itself

This question was raised directly during the project discussion and is
recorded here because the two modeling choices could easily be — wrongly —
seen as inconsistent.

**They model different objects.** The GARCH's Student's t choice concerns
the distribution of return innovations z(t), which show genuine fat tails
(empirical excess kurtosis ≈ 1.83, `GARCH_1_1.md`). This HMM instead models
log(σ(t)) **conditional on a regime**. Once observations are split by
regime, the residual distribution *within* a single regime can be
reasonably close to Gaussian — because the real extreme events are
absorbed by the **regime-switching structure itself** (they get assigned
to the "high volatility" state) rather than sitting as outliers within one
state's distribution. A mixture of several Gaussians (one per regime) can
collectively reproduce a fat-tailed *overall* distribution even though
each individual component is Gaussian — the fat tail is captured by the
regime structure, not by within-regime kurtosis.

**A practical constraint, also stated plainly rather than hidden**:
`hmmlearn`, the library used here, does not natively support Student's t
emissions — only Gaussian or Gaussian-mixture (`GMMHMM`). Implementing
Student's t emissions would require a different, less mature library
(e.g. `pomegranate`) or a custom-coded HMM, a complexity judged
disproportionate here given that section 4 shows the Gaussian
specification converges cleanly and produces well-separated, persistent
regimes.

## 6. What these results mean economically

The statistics in section 4 (convergence, separation, transition
probabilities) establish that the model is technically sound. This
section states plainly what they imply about the EUR/USD market itself —
which the technical results alone do not spell out.

### 6.1 The market spends most of its time NOT in a single "normal" state

Over 2010-2026, the sample splits roughly into 29% low volatility, 38%
normal volatility, 33% high volatility. In other words, the EUR/USD market
spends about **one third of all trading days in a stress/panic-level
volatility regime** — this is not a rare tail event confined to a handful
of crisis weeks; it is a recurring, roughly one-in-three-days state over a
16-year span. Economically, this pushes back on a framing where "panic" is
treated as an exceptional, short-lived departure from a normal baseline —
here it is closer to a third mode of operation that the market cycles
through regularly (wars, central bank shocks, COVID, inflation shocks,
etc., recurring roughly every few years across this sample).

### 6.2 Regimes are slow-moving, not day-to-day noise

The implied durations from section 4.3 (~127 days low vol, ~111 days high
vol, ~72 days normal) mean that, in economic terms, **once EUR/USD enters
a volatility regime, it tends to stay there for several months**, not days
or weeks. This matters operationally: a regime signal from this model is
not a short-term trading trigger — it is closer to a medium-term risk
posture indicator (e.g., useful for setting position sizing or hedging
policy over a quarter, not for daily decisions).

### 6.3 What the "current" classification (last 10 days: low volatility) means in practice

As of the end of the sample (2026-09-11), the model classifies the market
as being in a **low volatility** regime, and — per the transition
matrix — regimes of this type persist on average over 4 months once
entered. In economic terms: based purely on this signal, the market has
recently been calm and, historically, calm regimes tend to persist rather
than reverse abruptly. This is explicitly **not** a forecast that the
market will stay calm (the model has no crystal ball on the *timing* of
the next regime switch), and it says nothing about EUR/USD's future
direction (see the direction/magnitude distinction in
`magnitude_regression.md`) — only that, historically, the current type of
regime does not tend to flip overnight.

### 6.4 Link to the project's original operational ambition (objective b)

This connects directly to the "price range" framing from the project's
opening question (`methodology.md`, section 2): knowing the current
regime lets that range be set contextually rather than with one
fixed width. Combining this regime classification with the magnitude
relationship already established in `magnitude_regression.md` (higher
σ(t) → wider expected |r(t+1)|) gives a concrete, two-part operational
reading: e.g., "the market is currently in a low-volatility regime, which
historically persists for months, and the GARCH-implied volatility level
of σ(t) ≈ 0.30 corresponds to an expected day-to-day move around 0.2-0.3%"
— a regime-aware range, rather than a single global estimate applied
regardless of current market conditions. This combination has not yet been
formalized into a single deliverable (e.g. a function that outputs a
live price range given the current regime and σ(t)) — flagged as a
natural next step, not yet built.

## 7. Known limitations

- **Inherited GARCH instability** (documented in `garch_stability.md`):
  σ(t) used as input here comes from a single GARCH fit on the full
  2010-2026 sample, already shown to have unstable persistence across
  sub-periods. The regimes detected by this HMM may partly reflect that
  averaging artifact rather than purely genuine market regime shifts. This
  is the documented rationale for treating this HMM as a first-pass
  approach, with a Markov-Switching GARCH (re-estimating GARCH parameters
  per regime, directly addressing the instability) flagged as a possible
  future refinement rather than implemented at this stage.
- **"High volatility" is not "bubble"** (section 1.1) — this limitation is
  structural to any volatility-only regime model, not specific to this
  implementation, and should not be silently reinterpreted as such in any
  later summary of the project.
- Regime labels and boundaries depend on the arbitrary but standard choice
  of n_states = 3; not tested against 2 or 4 states as alternatives at
  this stage.

## 8. Files produced at this stage

- `src/regime_hmm.py` — `fit_regime_hmm` (multi-restart Gaussian HMM
  fitting with degenerate-fit detection), `summarize_regimes` (regime
  statistics and reordered transition matrix)
- `data/processed/regime_hmm_output.csv` — per-day regime classification
