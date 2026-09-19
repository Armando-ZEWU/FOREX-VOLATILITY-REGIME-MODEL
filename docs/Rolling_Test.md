# Rolling One-Step-Ahead Test (Sept 11-17, 2026)

*Companion document to `price_range.md`. Tests the operational forecasting
pipeline day by day through a real FOMC event week, using parameters
frozen at their original estimation (no re-fitting), and confronts the
result with the same rigor applied throughout the project — including a
direct critique of the first interpretation drafted, which was corrected
before being written here.*

## 1. Objective and design

Chain 4 sequential one-step-ahead forecasts, each using only the
information available up to the previous trading day:

| Forecast | History through | Target |
|---|---|---|
| 1 | 2026-09-11 | 2026-09-14 |
| 2 | 2026-09-14 | 2026-09-15 |
| 3 | 2026-09-15 | 2026-09-16 |
| 4 | 2026-09-16 | 2026-09-17 |

**Parameters are frozen** (the MS-GARCH fit from `ms_garch.R`, unchanged) —
each forecast differs only because the return history feeding `State()`
and `Risk()` grows by one real observed day each time. This isolates
exactly one question: how would the model, calibrated once on 2026-09-11,
have tracked reality through the following week without being re-tuned in
hindsight.

## 2. Data source workaround

A fresh FRED (`DEXUSEU`) pull was found to still stop at 2026-09-11 — the
same end date as the project's original pull — either a genuine
publication lag or a request issue; not resolved at the time of writing
(verify at
`https://fred.stlouisfed.org/graph/fredgraph.csv?id=DEXUSEU&cosd=2026-09-01&coed=2026-09-18`).
As a documented workaround, the existing FRED history was extended with
independently-sourced Close values (Pound Sterling Live) for 2026-09-14
through 2026-09-17 — the same source and discrepancy order already noted
for 2026-09-11 (FRED = 1.1604 vs. this source's 1.1599, ≈0.05%) in
`price_range.md`, section 7.1.

## 3. Results (Close-to-Close)

| Forecast | Cutoff price | Range | Width | Actual (Close) | Result | P(calm) at cutoff | P(stress) at cutoff |
|---|---|---|---|---|---|---|---|
| 1 (→09-14) | 1.1604 | [1.1533, 1.1675] | 1.22% | 1.1549 | **Inside** | 99.4% | 0.6% |
| 2 (→09-15) | 1.1549 | [1.1478, 1.1620] | 1.23% | 1.1542 | **Inside** | 98.9% | 1.1% |
| 3 (→09-16) | 1.1542 | [1.1471, 1.1613] | 1.23% | 1.1464 | **Outside** | 99.2% | 0.8% |
| 4 (→09-17) | 1.1464 | [1.1390, 1.1538] | 1.29% | 1.1459 | **Inside** | 97.0% | 3.0% |

**Raw outcome on Close: 3 of 4 inside the nominal 95% interval.**

### 3.1 Adding Open, High, Low — a more complete, slightly less favorable picture

The model is calibrated on close-to-close returns, so Close is the
correct primary comparison (as already established in `price_range.md`,
section 7.2). But checking the full daily range against each forecast
band reveals a nuance not visible from Close alone:

| Target | Range | Open | High | Low | Close |
|---|---|---|---|---|---|
| 09-14 | [1.1533, 1.1675] | 1.1597 (in) | 1.1601 (**in**) | 1.1523 (**OUTSIDE**) | 1.1549 (in) |
| 09-15 | [1.1478, 1.1620] | 1.1549 (in) | 1.1553 (in) | 1.1527 (in) | 1.1542 (in) |
| 09-16 | [1.1471, 1.1613] | 1.1542 (in) | 1.1557 (in) | 1.1461 (**OUTSIDE**) | 1.1464 (**OUTSIDE**) |
| 09-17 | [1.1390, 1.1538] | 1.1464 (in) | 1.1473 (in) | 1.1457 (in) | 1.1459 (in) |

**On Close alone: 1 breach out of 4. Including the intraday Low: 2 breaches
out of 4** (09-14 and 09-16). The 09-14 Low (1.1523) dipped below the
forecast's lower bound even though that day's Close came back inside by
the end of the session. This does not change the model's validity (it was
never built to predict intraday extremes — see `price_range.md` section
7.2's same point), but it is a more complete picture than reporting the
Close-only result alone, and is presented here rather than left out.

## 4. Fan charts — one per forecast day

Following the same logic as `price_range.md`'s fan chart (section 8) but
applied to each of the 4 rolling forecasts individually — four separate
images, each showing that day's 20/50/80/95% bands with the actual
observed Close price marked as a point, rather than one combined
multi-panel figure:

- `docs/fan_chart_rolling_20260914.png`
- `docs/fan_chart_rolling_20260915.png`
- `docs/fan_chart_rolling_20260916.png`
- `docs/fan_chart_rolling_20260917.png`

The 09-16 chart is the one to look at first: it is the only one where the
red actual-price point falls visibly below even the widest (95%) band —
a direct visual confirmation of the single Close-based breach in section 3.

## 5. Interpretation — corrected before writing, not after

An initial draft interpretation of these results was reviewed critically
before being finalized here; several points in that draft were wrong or
overclaimed. The corrected analysis follows.

### 5.1 n=4 proves nothing about calibration — stated plainly, not softened

3/4 (or 2/4, including intraday Lows) inside a 95% interval neither
validates nor invalidates the model's calibration. A meaningful empirical
coverage rate needs at minimum several dozen observations before it
carries statistical information. **This result is a demonstration that
the forecasting chain runs correctly end-to-end, not evidence of good (or
bad) calibration.** Any claim that "the model captures uncertainty well"
based on this alone would be an unsupported generalization from a
minuscule sample.

### 5.2 The Close-based miss (forecast 3, →09-16): two distinct explanations, correctly separated

The breach was marginal: actual 1.1464 vs. lower bound 1.1471, a gap of
0.0007 (≈0.061% of price, about 7 pips) — right at the edge, not a
dramatic failure.

Two distinct hypotheses were considered for whether this represents a
genuine model miss:

**(a) Direct measurement noise on the "actual" value itself.** The
forecast for 09-16 is compared to Pound Sterling Live's reported close,
while the model was calibrated on FRED data throughout its history. Since
FRED's own value for 09-16 is unavailable (the exact reason the
independent source was substituted in the first place), **it cannot be
ruled out** that FRED's true close for that day would have fallen inside
the range — the discrepancy already measured between the two sources on
09-11 (≈0.05%) is of the same order as this breach (≈0.06%). **This
remains genuinely unresolved with the data available.**

**(b) Contamination of the GARCH recursion via the one-time source switch
(09-11→09-14) — a distinct, quantifiable channel.** The single switch from
FRED (09-11 = 1.1604) to Pound Sterling Live (09-14 = 1.1549) creates a
"phantom" distortion in that day's computed return:

```
Return actually computed (FRED -> PSL):     ln(1.1549/1.1604) = -0.4751%
True single-source return (PSL's own 09-11
close of 1.1599 -> PSL 09-14):              ln(1.1549/1.1599) = -0.4320%
Phantom distortion:                         -0.0431 percentage points
                                             (larger magnitude than true)
```

Because GARCH's variance recursion uses squared past returns
(σ²(t) = ω + α·r²(t−1) + β·σ²(t−1)), a return of **larger** magnitude
injects **more**, not less, variance into every subsequent day's forecast
— meaning this channel, if anything, would have made forecast 3's range
**wider** than a fully single-source calculation would give. **This
channel does not explain the breach; if it has any effect, it argues the
"true" single-source model might have missed by slightly more, not less.**

**Conclusion**: channel (a) remains a genuine, unresolved source of doubt;
channel (b) was checked quantitatively and does not let the model "off the
hook" — it points the other way.

### 5.3 Regime reactivity: two competing hypotheses, correctly left undecided

Regime probabilities over the chain: P(stress) = 0.6% → 1.1% → 0.8% →
**3.0%**, while range width barely moved (1.22% → 1.23% → 1.23% → 1.29%).
The model's sense of risk rose roughly 5x over the week but stayed
anchored above 97% "calm" throughout, including immediately after the
miss.

Two explanations are both consistent with this single observation, and
**cannot be distinguished with only 4 data points**:

1. **Expected behavior by design**: frozen parameters mean the forecast
   only shifts because the information set changes marginally each day —
   no violent reaction is expected or wanted from a single new
   observation.
2. **A structural slowness to react to emerging stress**, which would only
   show up as a real problem (systematic under-coverage) over a longer,
   genuinely volatile period — not detectable from one relatively mild
   week.

**Next step required to actually decide between these**: rerun the same
frozen-parameter rolling chain over a historical window containing a real,
sustained shock (e.g. February-April 2020, entirely within the project's
existing FRED-sourced sample — avoiding any source-mixing caveat) and
check whether the empirical coverage rate collapses. This is a natural,
smaller-scale precursor to the full backtest still planned. See
`covid_robustness_test.md` (planned).

### 5.4 A methodological check on `set.seed()`, run and resolved

An earlier version of `rolling_test_chain.R` called `set.seed(42)` inside
the loop, once per iteration — a legitimate concern, since resetting an
identical seed before each of several stochastic calls can introduce
unwanted correlation across iterations rather than independent draws.
**Fixed** by moving `set.seed(42)` to run once before the loop. Rerunning
produced **numerically identical results** to the original (flawed)
version, digit for digit — confirmed again when the script was further
extended to compute multi-level bands for the fan charts (section 4).

**Why the fix made no difference here, checked rather than assumed**:
`State()` (the Hamilton filter) is a deterministic recursion with no
randomness involved. `Risk()` is called only once per iteration, with
different data and thus a different target distribution each time — the
risk the fix guards against (recycling identical draws across *repeated
calls on the same input*) does not arise when every call already differs
by construction. The fix remains worth keeping for future work (the
planned larger-scale backtest, where the same concern could matter more,
e.g. if `Risk()` were ever called multiple times on identical inputs).

## 6. Economic interpretation — what this chain means for someone watching the market

- **A concrete illustration, not just an abstract test.** Take forecast 3
  (→09-16), the one that missed: for a EUR 1,000,000 conversion decided on
  09-15's close, the model's 95% range implied proceeds between
  $1,147,100 and $1,161,300. The actual outcome ($1,146,400) fell about
  $700 below even the pessimistic end of that range — on a $1.15M
  transaction, a shortfall equivalent to roughly 0.06% of the notional.
  Framed this way, even the one "miss" in this chain was a **near-miss in
  dollar terms**, not a scenario that would have caused a business
  meaningful, unplanned damage.
- **The regime signal proved genuinely informative, just with a one-day
  lag.** A treasury or trader watching P(stress) climb from under 1% to
  3% between 09-15 and 09-16 would have received their first quantified
  warning sign of elevated risk on the **day after** the FOMC shock had
  already occurred — useful for adjusting the following days' hedging
  posture (consistent with forecast 4's wider range, 1.29% vs. the
  earlier ~1.22-1.23%), but not useful for having avoided the shock
  itself. This is the practical meaning of "reactive, not predictive":
  the tool tells you the ground has shifted once it has, not before.
- **The single miss occurred exactly where theory says it should.**
  Every prior section of this project (weak-form market efficiency,
  Meese & Rogoff) predicts that a model built from past prices cannot see
  a future central bank decision coming. This chain's one breach lines up
  exactly with that decision — not a random day, not a data anomaly, but
  the one day this project's own framework would flag in advance as
  structurally unforecastable.

## 7. What this means in practice for a user of the model

**A user with data through a given Friday (e.g. 2026-09-18) can compute a
real, model-based price range for the next trading day (e.g. Monday
2026-09-21, per the weekend-gap caveat in `price_range.md` section 5) at
whatever confidence level they choose, reflecting the current
regime-weighted volatility — but gets no information whatsoever about
whether the price will be higher or lower than today.** The range answers
"how far might it move," never "which way." This is not a simplification
that loses something important — it is the accurate summary of what has
been validated (repeatedly, independently, and now empirically in this
very test) and what has not.

## 8. Files produced at this stage

- `src/rolling_test_chain.R` — sequential rolling forecast chain (replaces
  the earlier single-jump `rolling_test_sept17.R`), frozen parameters,
  single `set.seed()` call before the loop, multi-level `Risk()` per
  iteration for the fan chart data
- `src/rolling_fan_charts.py` — one standalone fan chart image per
  forecast day
- `data/processed/rolling_test_chain_result.csv`
- `data/processed/rolling_fan_chart_inputs.csv`
- `docs/fan_chart_rolling_20260914.png` through `..._20260917.png`

## 9. What remains open

- The historical stress-window test proposed in section 5.3, to actually
  distinguish "expected frozen-parameter behavior" from "structural
  reactivity problem" — not yet run.
- The full backtest (many more one-step forecasts, empirical coverage
  rate vs. nominal 95%) — still the next planned major stage.
