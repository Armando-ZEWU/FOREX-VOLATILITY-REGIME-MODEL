# ms_garch.R
# Markov-Switching GARCH(1,1) estimation on EUR/USD log returns, using the
# peer-reviewed R package MSGARCH (Ardia, Bluteau, Boudt, Catania, Trottier,
# 2019, Journal of Statistical Software).
#
# Context: this project's GARCH work (docs/GARCH_1_1.md) and stability test
# (docs/garch_stability.md) were done in Python with the `arch` library, which
# has no Markov-Switching GARCH support. No comparably mature Python package
# exists for MS-GARCH; MSGARCH in R is the standard reference implementation.
# This R script is a deliberate, documented exception to the project's
# otherwise all-Python pipeline (see docs/ms_garch.md for the full
# discussion). Outputs are saved as CSV to be reloaded into the Python
# pipeline for further analysis/documentation.
#
# K = 2 regimes (not 3, unlike the HMM in regime_hmm.py): MS-GARCH estimation
# is substantially harder numerically than a Gaussian HMM on an already-
# computed scalar series -- it must jointly estimate omega, alpha, beta PER
# REGIME plus the transition matrix, under the path-dependency approximation
# (Gray, 1996) that makes MS-GARCH estimation tractable at all. Starting with
# 2 regimes follows the standard practice in the FX/equity MS-GARCH
# literature (e.g. Klaassen, 2002; Marcucci, 2005) before considering 3.

# install.packages("MSGARCH")  # uncomment if not already installed
library(MSGARCH)

# ---- 1. Load data ----
# Uses the same log returns already computed and validated in the Python
# pipeline (features.py), for full consistency with GARCH_1_1.md.
data <- read.csv("../data/processed/eurusd_log_returns.csv", stringsAsFactors = FALSE)
returns <- data$log_return
dates <- as.Date(data$Date)

cat("Loaded", length(returns), "observations.\n")
cat("Date range:", format(min(dates)), "to", format(max(dates)), "\n")

# ---- 2. Model specification ----
# 2 regimes, each a GARCH(1,1) ("sGARCH") with Student's t innovations
# ("std") -- matching the single-regime specification already validated
# in GARCH_1_1.md (Student's t over Normal).
#
# FIX: CreateSpec() rejects passing both a length-K vector in
# variance.spec/distribution.spec AND the K argument in switch.spec --
# these are two alternative ways to specify the same thing, not
# combinable. Using the single-regime-plus-K form here (K expands it
# automatically), per the error raised on the first run of this script.
spec <- CreateSpec(
  variance.spec = list(model = c("sGARCH")),
  distribution.spec = list(distribution = c("std")),
  switch.spec = list(do.mix = FALSE, K = 2)
)

print(spec)

# ---- 3. Maximum Likelihood estimation ----
cat("\nFitting MS-GARCH (this may take a while)...\n")
fit <- FitML(spec = spec, data = returns)

cat("\n=== Fit summary ===\n")
print(summary(fit))

# ---- 4. Per-regime parameters (the core question: do alpha, beta differ by regime?) ----
cat("\n=== Per-regime parameters ===\n")
state_fits <- ExtractStateFit(fit)
print(state_fits)

# ---- 5. Transition matrix ----
cat("\n=== Transition matrix ===\n")
trans_mat <- TransMat(fit)
print(trans_mat)

# ---- 6. Smoothed regime probabilities ----
# DIAGNOSTIC NOTE: the exact structure of State()'s output (array dimensions,
# names) is taken from the package documentation but has not been verified
# by direct execution on this dataset (this script was written without a
# working R environment available to test it). Inspect the printed
# structure below BEFORE trusting the extraction that follows -- if it
# doesn't match what's expected, adjust the indexing accordingly rather
# than assuming the code below is correct as-is.
state_probs_obj <- State(fit)
cat("\n=== Structure of State() output (inspect before trusting extraction below) ===\n")
str(state_probs_obj)

# Attempt extraction of smoothed probabilities -- ADJUST if str() above
# shows a different structure than expected.
smoothed_probs <- state_probs_obj$SmoothProb
cat("\nDimensions of smoothed_probs:", paste(dim(smoothed_probs), collapse=" x "), "\n")

# ---- 7. Save outputs for the Python pipeline ----
# Per-regime GARCH parameters are already fully captured in the printed
# summary and ExtractStateFit() output above (section 4) -- no separate
# extraction needed; that estimate table is transcribed directly into
# docs/ms_garch.md rather than re-parsed programmatically here.

# Transition matrix
write.csv(as.data.frame(trans_mat), "../data/processed/ms_garch_transition_matrix.csv", row.names = TRUE)

# Smoothed regime probabilities, aligned with dates
# CONFIRMED via MSGARCH documentation: SmoothProb has T+1 rows because
# row 1 represents the pre-sample prior (t=0, before any observation),
# not a real trading day. Rows 2:(T+1) correspond to the actual T
# observations (t=1,...,T) -- so we drop the FIRST row, not the last,
# to align with our T=4175 dates.
tryCatch({
  n_obs <- length(returns)
  regime_prob_df <- data.frame(
    Date = dates,
    log_return = returns,
    prob_regime_1 = smoothed_probs[2:(n_obs + 1), 1, 1],
    prob_regime_2 = smoothed_probs[2:(n_obs + 1), 1, 2]
  )
  write.csv(regime_prob_df, "../data/processed/ms_garch_regime_probs.csv", row.names = FALSE)
  cat("\nRegime probabilities saved successfully.\n")
}, error = function(e) {
  cat("\nERROR extracting regime probabilities -- structure differs from assumed.\n")
  cat("Error message:", conditionMessage(e), "\n")
  cat("Check the str() output above and adjust the indexing manually.\n")
})

cat("\nDone. Review all printed output above before proceeding.\n")

# ---- 8. Persist only the plain-numeric estimates (NOT the fit/spec object) ----
# fit$par, fit$loglik, fit$Inference$MatCoef sont de purs objets R (vecteur/liste/matrice).
# fit$spec porte un pointeur externe (module Rcpp) qui devient invalide après reload --
# on ne le sauvegarde jamais.
saveRDS(
  list(par = fit$par, loglik = fit$loglik, MatCoef = fit$Inference$MatCoef),
  "../data/processed/ms_garch_par.rds"
)
cat("\nParamètres sauvegardés dans ms_garch_par.rds (par numérique uniquement).\n")