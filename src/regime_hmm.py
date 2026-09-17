"""
regime_hmm.py
Detects hidden volatility regimes from the GARCH conditional volatility
sigma(t), using a 3-state Gaussian Hidden Markov Model.

IMPORTANT — labeling honesty (see docs/regime_hmm.md for the full
discussion): the 3 states detected here are volatility regimes, NOT
"bubble" states in the financial-bubble sense. A bubble's build-up phase
is often characterized by LOW, stable volatility (which is part of what
makes it look "safe" and attracts capital) — it's typically the burst,
not the bubble itself, that shows up as high volatility. A volatility-only
HMM cannot distinguish "normal calm market" from "bubble in formation";
both look identical in sigma(t). States are therefore labeled:
    - "low volatility"
    - "normal volatility"
    - "high volatility (stress/panic)"
NOT "normal / bubble / panic" as originally framed in methodology.md's
opening objective (b) -- that framing is revised here for accuracy.

Input variable: log(sigma_t), NOT sigma_t raw. This is a LEVEL
transformation (monotonic), not the log-DIFFERENCE (variation) used
elsewhere as delta_y_t -- do not confuse the two. The log transform is
used because GaussianHMM assumes each hidden state generates
approximately normally-distributed observations, and sigma_t (strictly
positive, likely right-skewed) is a poor fit for that assumption in its
raw form -- the same logic already applied when switching from raw
prices to log returns for EUR/USD itself.

Known limitation carried over from docs/garch_stability.md: sigma(t) used
here comes from a single GARCH fit on the full 2010-2026 sample, already
shown to be temporally unstable (persistence varies substantially across
sub-periods). The regimes detected below inherit that instability as a
potential source of bias -- flagged explicitly, not hidden, as the
documented rationale for treating this HMM as a first-pass approach
rather than a final model (a Markov-Switching GARCH, which re-estimates
GARCH parameters per regime, would address this more directly, at higher
implementation complexity).
"""

import pandas as pd
import numpy as np
from hmmlearn.hmm import GaussianHMM


def fit_regime_hmm(sigma_series, n_states=3, n_restarts=10, n_iter=1000):
    """
    Fit a Gaussian HMM on log(sigma_t), trying multiple random
    initializations and keeping the best-converged fit (highest
    log-likelihood). This guards against EM converging to a degenerate
    local optimum -- e.g., two states collapsing into near-identical
    distributions that flip daily instead of representing genuine,
    persistent regimes (a failure mode observed on the first run of this
    script, see docs/regime_hmm.md section on diagnostics).

    States are relabeled by ascending mean log-volatility, so state 0 is
    always "lowest volatility" regardless of hmmlearn's internal
    (arbitrary) component ordering.

    Parameters
    ----------
    sigma_series : pd.Series
        GARCH conditional volatility, sigma(t), indexed by date.
    n_states : int
        Number of hidden regimes. Default 3.
    n_restarts : int
        Number of random initializations to try; the best (by
        log-likelihood, among converged fits) is kept.
    n_iter : int
        Max EM iterations per restart.

    Returns
    -------
    pd.DataFrame
        Columns: sigma_t, log_sigma_t, state (relabeled, 0=lowest vol)
    model : GaussianHMM
        The best fitted model.
    relabel_map : dict
    """
    log_sigma = np.log(sigma_series).dropna()
    X = log_sigma.values.reshape(-1, 1)

    best_model = None
    best_score = -np.inf
    n_converged = 0

    for seed in range(n_restarts):
        candidate = GaussianHMM(
            n_components=n_states,
            covariance_type="diag",
            n_iter=n_iter,
            random_state=seed,
        )
        candidate.fit(X)
        converged = candidate.monitor_.converged
        score = candidate.score(X)
        if converged:
            n_converged += 1
        print(f"  Restart {seed}: converged={converged}, log-likelihood={score:.2f}")
        if score > best_score:
            best_score = score
            best_model = candidate

    print(f"\n{n_converged}/{n_restarts} restarts converged. "
          f"Best log-likelihood: {best_score:.2f}")

    model = best_model
    raw_states = model.predict(X)

    # Check for degenerate/duplicate states: if any two states have
    # near-identical means, warn explicitly rather than silently
    # presenting them as distinct regimes.
    means = model.means_.flatten()
    for i in range(len(means)):
        for j in range(i + 1, len(means)):
            if abs(means[i] - means[j]) < 0.05:
                print(f"\nWARNING: states {i} and {j} have near-identical "
                      f"means ({means[i]:.4f} vs {means[j]:.4f}) -- likely "
                      f"a degenerate fit, not two genuine regimes. Consider "
                      f"reducing n_states or inspecting the transition "
                      f"matrix for near-daily flipping between them.")

    state_means = model.means_.flatten()
    order = np.argsort(state_means)
    relabel_map = {old: new for new, old in enumerate(order)}
    relabeled_states = np.array([relabel_map[s] for s in raw_states])

    out = pd.DataFrame({
        "sigma_t": sigma_series.loc[log_sigma.index],
        "log_sigma_t": log_sigma,
        "state": relabeled_states,
    })

    return out, model, relabel_map


def summarize_regimes(df, model, relabel_map, label_names=None):
    """
    Print a human-readable summary: state means/std (in original sigma
    units, via exp of the log-scale mean as an approximation), state
    frequencies, and the transition matrix (reordered to match the
    relabeled state indices).
    """
    if label_names is None:
        label_names = {0: "low volatility", 1: "normal volatility", 2: "high volatility (stress/panic)"}

    n_states = model.n_components
    order = sorted(relabel_map, key=relabel_map.get)  # old indices in new order

    print("=== Regime summary (log_sigma_t scale) ===")
    for new_idx, old_idx in enumerate(order):
        mean_log = model.means_[old_idx][0]
        std_log = np.sqrt(model.covars_[old_idx][0][0])
        freq = (df["state"] == new_idx).mean()
        name = label_names.get(new_idx, f"state {new_idx}")
        print(f"State {new_idx} ({name}): "
              f"mean(log sigma)={mean_log:.4f}, std={std_log:.4f}, "
              f"freq={freq:.1%}, approx sigma level={np.exp(mean_log):.4f}")

    # Reorder transition matrix to match relabeled states
    reordered_transmat = np.zeros((n_states, n_states))
    for i_new, i_old in enumerate(order):
        for j_new, j_old in enumerate(order):
            reordered_transmat[i_new, j_new] = model.transmat_[i_old, j_old]

    print("\n=== Transition matrix (rows: from, cols: to; relabeled order) ===")
    print(pd.DataFrame(
        reordered_transmat,
        index=[f"from {label_names.get(i, i)}" for i in range(n_states)],
        columns=[f"to {label_names.get(i, i)}" for i in range(n_states)],
    ).round(4))


if __name__ == "__main__":
    shocks = pd.read_csv(
        "../data/processed/eurusd_garch_shocks.csv",
        index_col="Date", parse_dates=True
    )
    sigma_t = shocks["conditional_volatility"]

    df, model, relabel_map = fit_regime_hmm(sigma_t, n_states=3)
    summarize_regimes(df, model, relabel_map)

    print("\n=== Last 10 days, with regime label ===")
    label_names = {0: "low volatility", 1: "normal volatility", 2: "high volatility (stress/panic)"}
    df["regime_label"] = df["state"].map(label_names)
    print(df.tail(10))

    df.to_csv("../data/processed/regime_hmm_output.csv")