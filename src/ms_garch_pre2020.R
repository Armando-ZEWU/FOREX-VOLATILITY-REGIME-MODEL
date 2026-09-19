# ms_garch_pre2020.R
# Re-estimates a SEPARATE MS-GARCH(K=2) model using ONLY data through
# 2019-12-31 -- a model that has genuinely never seen the COVID shock,
# needed for a true out-of-sample robustness test (see the discussion in
# docs/covid_robustness_test.md, section 1: the original ms_garch.R model
# was calibrated on the full 2010-2026 sample, INCLUDING the COVID period
# itself, which would make any "test" on that period circular, not a real
# robustness check).
#
# Same specification as ms_garch.R (K=2, sGARCH, Student's t), applied to
# a strictly earlier-truncated sample. Diagnostics printed with the same
# rigor as the original fit, since a silently-worse-converged model here
# would undermine the whole robustness test built on top of it.

library(MSGARCH)

data <- read.csv("../data/processed/eurusd_log_returns.csv", stringsAsFactors = FALSE)
data$Date <- as.Date(data$Date)

cutoff <- as.Date("2019-12-31")
data_pre2020 <- data[data$Date <= cutoff, ]
returns_pre2020 <- data_pre2020$log_return

cat("Pre-2020 sample:", nrow(data_pre2020), "observations,",
    format(min(data_pre2020$Date)), "to", format(max(data_pre2020$Date)), "\n")

spec <- CreateSpec(
  variance.spec = list(model = c("sGARCH")),
  distribution.spec = list(distribution = c("std")),
  switch.spec = list(do.mix = FALSE, K = 2)
)

cat("\nFitting MS-GARCH on pre-2020 data only...\n")
fit_pre2020 <- FitML(spec = spec, data = returns_pre2020)

cat("\n=== Fit summary (pre-2020 only) ===\n")
print(summary(fit_pre2020))

cat("\n=== Comparison to the full-sample fit (docs/ms_garch.md) ===\n")
cat("Full-sample (2010-2026): LL=-2806.64, AIC=5633.27, BIC=5696.64\n")
cat(sprintf("Pre-2020 only:           LL=%.2f, AIC=%.2f, BIC=%.2f\n",
            fit_pre2020$loglik, fit_pre2020$AIC, fit_pre2020$BIC))
cat("(Not directly comparable -- different sample sizes -- shown for context only.)\n")

# Save only the plain-numeric parameters, not the fit/spec object itself
# -- same Rcpp external-pointer limitation documented in ms_garch.R.
saveRDS(
  list(par = fit_pre2020$par, loglik = fit_pre2020$loglik,
       MatCoef = fit_pre2020$Inference$MatCoef),
  "../data/processed/ms_garch_par_pre2020.rds"
)
cat("\nParameters saved to ms_garch_par_pre2020.rds\n")
