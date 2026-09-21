# full_backtest.R
# Full expanding-window out-of-sample backtest, 2013-2026.
#
# STRUCTURE (two nested loops, deliberately different cost profiles):
#   OUTER loop (~14 iterations): one full MS-GARCH(K=2) re-estimation per
#     year, using an EXPANDING training window (2010-2012 -> predicts
#     2013; 2010-2013 -> predicts 2014; ... 2010-2025 -> predicts 2026).
#     This is the expensive, convergence-sensitive step.
#   INNER loop (~252 iterations per outer step, ~3500 total): one-step-
#     ahead forecasts within the following year, using the FROZEN
#     parameters from that year's outer-loop estimation -- cheap,
#     mirrors covid_robustness_test.R's design exactly.
#
# COMPUTATIONAL DECISION: only the 95% interval is computed here (not the
# 20/50/80/95% multi-level fan chart used for the COVID test), to keep
# runtime manageable across ~3500 forecast steps. A simpler visualization
# can be built afterward from this single-level output if needed.
#
# CONVERGENCE SAFETY: each outer-loop fit is wrapped in tryCatch -- a
# single problematic year must not silently corrupt or halt the entire
# multi-hour run. Convergence red flags (alpha+beta near the IGARCH
# boundary, as seen in garch_stability.md; imprecise nu, as seen in
# ms_garch_pre2020.R) are checked and printed as warnings, not hidden.

library(MSGARCH)

returns_df <- read.csv("../data/processed/eurusd_log_returns.csv", stringsAsFactors = FALSE)
returns_df$Date <- as.Date(returns_df$Date)
prices_df <- read.csv("../data/raw/eurusd_daily.csv", stringsAsFactors = FALSE)
names(prices_df)[1:2] <- c("Date", "Close")
prices_df$Date <- as.Date(prices_df$Date)

spec <- CreateSpec(
  variance.spec = list(model = c("sGARCH")),
  distribution.spec = list(distribution = c("std")),
  switch.spec = list(do.mix = FALSE, K = 2)
)

# Training cutoffs: end of 2012 through end of 2025 -- each predicts the
# following calendar year. First fold uses 2010-2012 (3 years, ~750 obs)
# as agreed; expect this and the next few folds to be less precisely
# estimated than later ones with more data (flagged, not hidden).
training_cutoffs <- as.Date(paste0(2012:2025, "-12-31"))
test_years <- 2013:2026

all_results <- data.frame()
fold_diagnostics <- data.frame()

set.seed(42)  # once, before everything

for (f in seq_along(training_cutoffs)) {
  cutoff <- training_cutoffs[f]
  test_year <- test_years[f]
  
  cat(sprintf("\n========================================\n"))
  cat(sprintf("FOLD %d/%d: training through %s, testing %d\n",
              f, length(training_cutoffs), format(cutoff), test_year))
  cat(sprintf("========================================\n"))
  cat("Start time:", format(Sys.time()), "\n")
  
  train_returns <- returns_df$log_return[returns_df$Date <= cutoff]
  cat("Training observations:", length(train_returns), "\n")
  
  fit_result <- tryCatch({
    FitML(spec = spec, data = train_returns)
  }, error = function(e) {
    cat("FIT FAILED for fold", f, ":", conditionMessage(e), "\n")
    NULL
  })
  
  if (is.null(fit_result)) {
    fold_diagnostics <- rbind(fold_diagnostics, data.frame(
      fold = f, test_year = test_year, converged = FALSE,
      alpha_beta_1 = NA, alpha_beta_2 = NA, nu_1 = NA, nu_2 = NA,
      nu_1_se = NA, nu_2_se = NA,
      P_1_1 = NA, P_2_1 = NA, P_1_2 = NA, P_2_2 = NA
    ))
    next
  }
  
  par <- fit_result$par
  ab1 <- par["alpha1_1"] + par["beta_1"]
  ab2 <- par["alpha1_2"] + par["beta_2"]
  nu1 <- par["nu_1"]; nu2 <- par["nu_2"]
  nu1_se <- fit_result$Inference$MatCoef["nu_1", "Std. Error"]
  nu2_se <- fit_result$Inference$MatCoef["nu_2", "Std. Error"]
  # Transition matrix elements -- added after the fold 6 (2018) anomaly
  # (docs/full_backtest.md, section 5) could not be fully diagnosed
  # without them: was regime 2 rarely ENTERED (P_1_2 low), quickly EXITED
  # once entered (P_2_2 low), or both? P_1_1 = P(stay in regime 1),
  # P_2_1 = P(regime 2 -> regime 1); P_1_2 = 1-P_1_1, P_2_2 = 1-P_2_1.
  p11 <- par["P_1_1"]
  p21 <- par["P_2_1"]
  
  cat(sprintf("alpha+beta: regime1=%.4f regime2=%.4f\n", ab1, ab2))
  cat(sprintf("nu: regime1=%.2f (SE=%.2f) regime2=%.2f (SE=%.2f)\n",
              nu1, nu1_se, nu2, nu2_se))
  cat(sprintf("Transition: P(stay1)=%.4f P(2->1)=%.4f [implies P(stay2)=%.4f P(1->2)=%.4f]\n",
              p11, p21, 1 - p21, 1 - p11))
  
  if (ab1 > 0.999 || ab2 > 0.999) {
    cat("WARNING: persistence near IGARCH boundary (>0.999) -- see garch_stability.md precedent.\n")
  }
  if (nu2_se > nu2) {
    cat("WARNING: nu_2 standard error exceeds the estimate itself -- poorly identified tail (see ms_garch_pre2020.R precedent).\n")
  }
  
  fold_diagnostics <- rbind(fold_diagnostics, data.frame(
    fold = f, test_year = test_year, converged = TRUE,
    alpha_beta_1 = ab1, alpha_beta_2 = ab2, nu_1 = nu1, nu_2 = nu2,
    nu_1_se = nu1_se, nu_2_se = nu2_se,
    P_1_1 = p11, P_2_1 = p21, P_1_2 = 1 - p11, P_2_2 = 1 - p21
  ))
  
  # ---- Inner loop: daily forecasts through test_year, frozen `par` ----
  test_indices <- which(format(returns_df$Date, "%Y") == as.character(test_year))
  cat("Forecasting", length(test_indices), "trading days in", test_year, "...\n")
  
  for (idx in test_indices) {
    if (idx < 2) next
    target_date <- returns_df$Date[idx]
    returns_hist <- returns_df$log_return[1:(idx - 1)]
    cutoff_date_day <- returns_df$Date[idx - 1]
    last_price_hist <- prices_df$Close[prices_df$Date == cutoff_date_day]
    actual_price <- prices_df$Close[prices_df$Date == target_date]
    
    if (length(last_price_hist) != 1 || length(actual_price) != 1) next
    
    state_probs_obj <- tryCatch(
      State(object = spec, par = par, data = returns_hist),
      error = function(e) NULL
    )
    if (is.null(state_probs_obj)) next
    pred_prob_now <- state_probs_obj$PredProb[dim(state_probs_obj$PredProb)[1], 1, ]
    
    risk_obj <- tryCatch(
      Risk(object = spec, par = par, data = returns_hist,
           alpha = c(0.025, 0.975), nahead = 1L, do.es = FALSE, do.its = FALSE),
      error = function(e) NULL
    )
    if (is.null(risk_obj)) next
    var_values <- as.numeric(risk_obj$VaR)
    
    p_min <- last_price_hist * exp(var_values[1] / 100)
    p_max <- last_price_hist * exp(var_values[2] / 100)
    inside <- (actual_price >= p_min & actual_price <= p_max)
    
    all_results <- rbind(all_results, data.frame(
      fold = f, test_year = test_year, target_date = target_date,
      p_min = p_min, p_max = p_max, actual_price = actual_price,
      inside_range = inside,
      prob_calm = pred_prob_now[1], prob_stress = pred_prob_now[2]
    ))
  }
  
  cat("Fold", f, "done at", format(Sys.time()), "\n")
  # Save incrementally after each fold, so a crash mid-run doesn't lose
  # everything already computed.
  write.csv(all_results, "../data/processed/full_backtest_result.csv", row.names = FALSE)
  write.csv(fold_diagnostics, "../data/processed/full_backtest_fold_diagnostics.csv", row.names = FALSE)
}

cat("\n\n========================================\n")
cat("FULL BACKTEST COMPLETE\n")
cat("========================================\n")
cat("Total forecasts:", nrow(all_results), "\n")
coverage <- mean(all_results$inside_range)
n_breaches <- sum(!all_results$inside_range)
cat(sprintf("Overall empirical coverage: %d/%d = %.2f%% (nominal 95%%)\n",
            nrow(all_results) - n_breaches, nrow(all_results), coverage * 100))
binom_test <- binom.test(n_breaches, nrow(all_results), p = 0.05, alternative = "greater")
cat(sprintf("One-sided binomial test (H1: true breach rate > 5%%): p = %.5f\n", binom_test$p.value))

cat("\n=== Coverage by year ===\n")
by_year <- aggregate(inside_range ~ test_year, data = all_results, FUN = mean)
print(by_year)

cat("\nFull results saved to full_backtest_result.csv\n")
cat("Fold diagnostics saved to full_backtest_fold_diagnostics.csv\n")