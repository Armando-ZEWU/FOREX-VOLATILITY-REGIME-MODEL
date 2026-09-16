"""
garch_diagnostics.py
Diagnostic checks on a fitted GARCH model:
1. Ljung-Box test on squared standardized residuals (remaining ARCH effect?)
2. QQ-plot of standardized residuals vs Normal (fat tails check)
3. ARCH-LM test (built-in, from the arch library) — run on STANDARDIZED
   residuals, since the raw-residual version will (correctly) reject
   almost always and is not informative about model adequacy.

FIX (2026-09-15): the previous version of this script's __main__ block
always fit a Normal-distribution GARCH, regardless of which model you
wanted to diagnose. This version fits and diagnoses BOTH the Normal and
Student's t models explicitly, side by side, so there is no ambiguity
about which result you are looking at.
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy import stats
from statsmodels.stats.diagnostic import acorr_ljungbox


def run_diagnostics(result, shocks_df, label="model", save_qqplot=True):
    """
    Run diagnostic checks on a fitted GARCH result.

    Parameters
    ----------
    result : arch.univariate.base.ARCHModelResult
        The fitted GARCH result (from garch_model.fit_garch).
    shocks_df : pd.DataFrame
        Output of garch_model.extract_shock(result).
    label : str
        Short identifier used in printed output and saved filenames
        (e.g. "normal", "student_t") so multiple diagnostic runs don't
        overwrite each other.
    save_qqplot : bool
        If True, saves a QQ-plot PNG to ../docs/.

    Returns
    -------
    dict
        Summary of key diagnostic statistics, for easy side-by-side
        comparison across models.
    """
    std_resid = shocks_df["standardized_residual"].dropna()

    print(f"\n{'='*60}\nDIAGNOSTICS FOR: {label}\n{'='*60}")

    # 1. Ljung-Box on squared standardized residuals
    lb_result = acorr_ljungbox(std_resid**2, lags=[10, 20], return_df=True)
    print("\n--- Ljung-Box test on squared standardized residuals ---")
    print(lb_result)
    print(
        "Interpretation: p-values > 0.05 => fail to reject H0 => "
        "no significant remaining ARCH effect (good)."
    )

    # 2. QQ-plot vs Normal distribution
    if save_qqplot:
        fig, ax = plt.subplots(figsize=(6, 6))
        stats.probplot(std_resid, dist="norm", plot=ax)
        ax.set_title(f"QQ-plot: Standardized Residuals vs Normal ({label})")
        plt.tight_layout()
        out_path = f"../docs/qqplot_std_residuals_{label}.png"
        plt.savefig(out_path, dpi=150)
        plt.close(fig)
        print(f"\nQQ-plot saved to {out_path}")

    # 3. ARCH-LM test on STANDARDIZED residuals (the informative version)
    arch_lm = result.arch_lm_test(lags=10, standardized=True)
    print("\n--- ARCH-LM test on STANDARDIZED residuals ---")
    print(f"Statistic: {arch_lm.stat:.4f}   P-value: {arch_lm.pval:.4f}")
    print(
        "Interpretation: p-value > 0.05 => no remaining conditional "
        "heteroskedasticity in the standardized residuals (good)."
    )

    # Summary stats on standardized residuals (should be ~ mean 0, std 1)
    print("\n--- Standardized residual summary (target: mean~0, std~1) ---")
    print(std_resid.describe())

    # Excess kurtosis check (Normal = 0)
    kurt = stats.kurtosis(std_resid)
    print(f"\nExcess kurtosis: {kurt:.3f}")
    if kurt > 1:
        print("-> Still meaningfully above 0: fat tails not fully absorbed.")
    elif kurt > 0.3:
        print("-> Mildly above 0: some residual fat-tail behavior remains.")
    else:
        print("-> Close to 0: fat tails reasonably well absorbed by the model.")

    return {
        "label": label,
        "aic": result.aic,
        "bic": result.bic,
        "log_likelihood": result.loglikelihood,
        "ljung_box_p10": lb_result.loc[10, "lb_pvalue"],
        "arch_lm_p_standardized": arch_lm.pval,
        "excess_kurtosis": kurt,
    }


if __name__ == "__main__":
    from garch_model import fit_garch, extract_shock

    returns = pd.read_csv(
        "../data/processed/eurusd_log_returns.csv",
        index_col="Date", parse_dates=True
    )["log_return"]

    # Fit and diagnose BOTH models explicitly — no ambiguity about which
    # is which.
    result_normal = fit_garch(returns, dist="normal")
    shocks_normal = extract_shock(result_normal)
    summary_normal = run_diagnostics(result_normal, shocks_normal, label="normal")

    result_t = fit_garch(returns, dist="t")
    shocks_t = extract_shock(result_t)
    summary_t = run_diagnostics(result_t, shocks_t, label="student_t")

    # Side-by-side comparison table
    comparison = pd.DataFrame([summary_normal, summary_t]).set_index("label")
    print(f"\n{'='*60}\nSIDE-BY-SIDE COMPARISON\n{'='*60}")
    print(comparison.to_string())