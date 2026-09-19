# rolling_test_chain.R
# Sequential rolling one-step-ahead test: forecast each of Sept 14, 15,
# 16, 17 using only the data available up to the PREVIOUS trading day,
# then compare each forecast to what actually happened -- a chain of 4
# independent one-step tests, not a single jump from Sept 11 to Sept 17.
#
# METHODOLOGICAL DECISION (unchanged from the original design): the
# already-fitted MS-GARCH parameters (ms_garch_par.rds) are kept FIXED
# throughout -- no re-estimation at any step. Each forecast only differs
# because the information set (the return history feeding State()/Risk())
# grows by one more real, observed day each time. This isolates what we
# actually want to test: given the model as calibrated on 2026-09-11,
# how well would it have tracked reality day by day through the FOMC week,
# without being re-tuned in hindsight.
#
# DATA SOURCE NOTE: a fresh FRED pull (DEXUSEU) was found to still stop at
# 2026-09-11 -- the same end date as the project's original data pull --
# either a genuine current FRED publication lag or a request issue.
# Verify directly at:
#   https://fred.stlouisfed.org/graph/fredgraph.csv?id=DEXUSEU&cosd=2026-09-01&coed=2026-09-18
# before assuming this is permanent. As a documented workaround, this
# script extends the existing FRED-based history (eurusd_daily.csv,
# through 2026-09-11) with independently-sourced Close values for
# 2026-09-14 through 2026-09-17 (Pound Sterling Live) -- the same source
# and the same ~0.05% discrepancy already noted and accepted for
# 2026-09-11 in docs/price_range.md section 7.1 (FRED=1.1604 vs. this
# source's 1.1599 for that day). Not a silent substitution.

library(MSGARCH)

raw <- read.csv("../data/raw/eurusd_daily.csv", stringsAsFactors = FALSE)
names(raw)[1:2] <- c("Date", "Close")
raw$Date <- as.Date(raw$Date)

extension <- data.frame(
  Date = as.Date(c("2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17")),
  Close = c(1.1549, 1.1542, 1.1464, 1.1459)
)
cat("Extending FRED history (through", format(max(raw$Date)),
    ") with", nrow(extension), "days from an independent source",
    "(Pound Sterling Live) -- see docs/price_range.md for the caveat.\n")

raw <- rbind(raw[, c("Date", "Close")], extension)
raw <- raw[order(raw$Date), ]
raw <- raw[!duplicated(raw$Date), ]
cat("Combined data range:", format(min(raw$Date)), "to", format(max(raw$Date)), "\n")

# Chain of (cutoff, target) pairs: forecast target using data through cutoff
cutoffs <- as.Date(c("2026-09-11", "2026-09-14", "2026-09-15", "2026-09-16"))
targets <- as.Date(c("2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17"))

saved <- readRDS("../data/processed/ms_garch_par.rds")
par <- saved$par
spec <- CreateSpec(
  variance.spec = list(model = c("sGARCH")),
  distribution.spec = list(distribution = c("std")),
  switch.spec = list(do.mix = FALSE, K = 2)
)

confidence_level <- 0.95
alpha_lower <- (1 - confidence_level) / 2
alpha_upper <- 1 - alpha_lower

confidence_levels <- c(0.20, 0.50, 0.80, 0.95)  # same levels as ms_garch_forecast.R's fan chart
alpha_pairs <- lapply(confidence_levels, function(cl) c((1-cl)/2, 1-(1-cl)/2))
alpha_vector <- sort(unique(unlist(alpha_pairs)))

results <- data.frame()
fan_data <- data.frame()  # one row per (target_date, confidence_level), for individual daily fan charts

# set.seed called ONCE before the loop, not per-iteration: resetting the
# seed inside the loop would make each iteration draw from the same
# starting point in the RNG stream, an artifact worth avoiding for any
# future run with a larger number of iterations (e.g. the full backtest).
set.seed(42)

for (i in seq_along(cutoffs)) {
  cutoff <- cutoffs[i]
  target <- targets[i]
  
  history <- raw[raw$Date <= cutoff, ]
  holdout <- raw[raw$Date == target, ]
  
  if (nrow(holdout) == 0) {
    cat(sprintf("\nSkipping %s -> %s: no data found for target date.\n",
                format(cutoff), format(target)))
    next
  }
  
  history$log_return <- c(NA, diff(log(history$Close)) * 100)
  returns_hist <- history$log_return[!is.na(history$log_return)]
  last_price_hist <- tail(history$Close, 1)
  
  state_probs_obj <- State(object = spec, par = par, data = returns_hist)
  pred_prob_now <- state_probs_obj$PredProb[dim(state_probs_obj$PredProb)[1], 1, ]
  
  # Multi-level Risk() call, same alpha-vector approach as ms_garch_forecast.R
  risk_multi <- Risk(
    object = spec, par = par, data = returns_hist,
    alpha = alpha_vector, nahead = 1L,
    do.es = FALSE, do.its = FALSE
  )
  var_row <- as.numeric(risk_multi$VaR[1, ])
  names(var_row) <- alpha_vector
  actual_price <- holdout$Close
  
  for (cl in confidence_levels) {
    a_low <- (1 - cl) / 2
    a_high <- 1 - a_low
    p_min_cl <- last_price_hist * exp(var_row[as.character(a_low)] / 100)
    p_max_cl <- last_price_hist * exp(var_row[as.character(a_high)] / 100)
    fan_data <- rbind(fan_data, data.frame(
      cutoff_date = cutoff, target_date = target,
      confidence_level = cl, p_min = p_min_cl, p_max = p_max_cl,
      actual_price = actual_price
    ))
  }
  
  # Keep the 95% level as the operational summary (matches earlier results)
  q_low <- var_row[as.character(0.025)]
  q_high <- var_row[as.character(0.975)]
  p_min <- last_price_hist * exp(q_low / 100)
  p_max <- last_price_hist * exp(q_high / 100)
  inside <- (actual_price >= p_min & actual_price <= p_max)
  
  cat(sprintf("\n%s (close=%.4f) -> forecast %s: [%.4f, %.4f] | actual: %.4f | %s\n",
              format(cutoff), last_price_hist, format(target), p_min, p_max,
              actual_price, ifelse(inside, "INSIDE", "OUTSIDE")))
  cat(sprintf("  Regime probs at %s: calm=%.1f%%, stress=%.1f%%\n",
              format(cutoff), pred_prob_now[1]*100, pred_prob_now[2]*100))
  
  results <- rbind(results, data.frame(
    cutoff_date = cutoff,
    cutoff_price = last_price_hist,
    target_date = target,
    p_min = p_min,
    p_max = p_max,
    range_width_pct = (p_max - p_min) / last_price_hist,
    actual_price = actual_price,
    inside_range = inside,
    prob_calm = pred_prob_now[1],
    prob_stress = pred_prob_now[2]
  ))
}

write.csv(fan_data, "../data/processed/rolling_fan_chart_inputs.csv", row.names = FALSE)
cat("\nFan chart inputs (multi-level, per day) saved to rolling_fan_chart_inputs.csv\n")

cat("\n=== Full chain summary ===\n")
print(results)

write.csv(results, "../data/processed/rolling_test_chain_result.csv", row.names = FALSE)
cat("\nSaved to rolling_test_chain_result.csv\n")