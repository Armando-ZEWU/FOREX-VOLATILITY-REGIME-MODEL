# covid_robustness_test.R
# TRUE out-of-sample rolling one-step-ahead test through the COVID shock:
# forecasts every trading day from 2020-01-01 through 2020-04-30, using
# ONLY the MS-GARCH parameters estimated on pre-2020 data
# (ms_garch_par_pre2020.rds, from ms_garch_pre2020.R) -- a model that has
# genuinely never seen the COVID period. Parameters remain FROZEN
# throughout (same design decision as rolling_test_chain.R); only the
# information set (return history) grows day by day as the window
# progresses.
#
# SINGLE SOURCE: unlike the September rolling test, this window is
# entirely within the project's original FRED-sourced data
# (eurusd_daily.csv) -- no source-switching caveat applies here.
#
# PURPOSE: with ~80 trading days rather than 4, this is the first test in
# the project large enough to compute a genuinely informative empirical
# coverage rate (% of days the actual return falls inside the 95%
# interval), comparable to the nominal 95% -- the question the September
# rolling test (n=4) explicitly could not answer (docs/rolling_test.md,
# section 5.1).
#
# KNOWN LIMITATION carried forward from ms_garch_pre2020.R: nu_2 (the
# stress regime's tail parameter) is very imprecisely estimated in the
# pre-2020 fit (71.73, SE=202.05, not significant) -- any extreme-tail
# forecast under regime 2 during this test should be read with that
# imprecision in mind, not treated as equally reliable as regime 1's.

library(MSGARCH)

# ---- 1. Load data (single FRED source, already covers 2020 natively) ----
returns_df <- read.csv("../data/processed/eurusd_log_returns.csv", stringsAsFactors = FALSE)
returns_df$Date <- as.Date(returns_df$Date)
prices_df <- read.csv("../data/raw/eurusd_daily.csv", stringsAsFactors = FALSE)
names(prices_df)[1:2] <- c("Date", "Close")
prices_df$Date <- as.Date(prices_df$Date)

# ---- 2. Load FROZEN pre-2020 parameters ----
saved <- readRDS("../data/processed/ms_garch_par_pre2020.rds")
par <- saved$par
spec <- CreateSpec(
  variance.spec = list(model = c("sGARCH")),
  distribution.spec = list(distribution = c("std")),
  switch.spec = list(do.mix = FALSE, K = 2)
)

# ---- 3. Define the test window ----
window_start <- as.Date("2020-01-01")
window_end <- as.Date("2020-04-30")
target_indices <- which(returns_df$Date >= window_start & returns_df$Date <= window_end)

cat("Test window:", format(window_start), "to", format(window_end),
    "--", length(target_indices), "trading days.\n")

confidence_levels <- c(0.20, 0.50, 0.80, 0.95)
alpha_pairs <- lapply(confidence_levels, function(cl) c((1-cl)/2, 1-(1-cl)/2))
alpha_vector <- sort(unique(unlist(alpha_pairs)))

results <- data.frame()
fan_data <- data.frame()

set.seed(42)  # once, before the loop (see rolling_test_chain.R's fix)

for (idx in target_indices) {
  target_date <- returns_df$Date[idx]

  # History: all returns realized up to and including the PREVIOUS trading
  # day (idx-1) -- the target day's own return is excluded, exactly like
  # rolling_test_chain.R.
  if (idx < 2) next  # safety, shouldn't trigger given the window
  returns_hist <- returns_df$log_return[1:(idx - 1)]
  cutoff_date <- returns_df$Date[idx - 1]
  last_price_hist <- prices_df$Close[prices_df$Date == cutoff_date]

  if (length(last_price_hist) != 1) {
    cat("Skipping", format(target_date), "-- couldn't uniquely match cutoff price.\n")
    next
  }

  actual_price <- prices_df$Close[prices_df$Date == target_date]
  if (length(actual_price) != 1) {
    cat("Skipping", format(target_date), "-- couldn't uniquely match actual price.\n")
    next
  }

  state_probs_obj <- State(object = spec, par = par, data = returns_hist)
  pred_prob_now <- state_probs_obj$PredProb[dim(state_probs_obj$PredProb)[1], 1, ]

  risk_multi <- Risk(
    object = spec, par = par, data = returns_hist,
    alpha = alpha_vector, nahead = 1L,
    do.es = FALSE, do.its = FALSE
  )
  var_row <- as.numeric(risk_multi$VaR[1, ])
  names(var_row) <- alpha_vector

  for (cl in confidence_levels) {
    a_low <- (1 - cl) / 2
    a_high <- 1 - a_low
    p_min_cl <- last_price_hist * exp(var_row[as.character(a_low)] / 100)
    p_max_cl <- last_price_hist * exp(var_row[as.character(a_high)] / 100)
    fan_data <- rbind(fan_data, data.frame(
      target_date = target_date, confidence_level = cl,
      p_min = p_min_cl, p_max = p_max_cl, actual_price = actual_price
    ))
  }

  q_low <- var_row[as.character(0.025)]
  q_high <- var_row[as.character(0.975)]
  p_min <- last_price_hist * exp(q_low / 100)
  p_max <- last_price_hist * exp(q_high / 100)
  inside <- (actual_price >= p_min & actual_price <= p_max)

  results <- rbind(results, data.frame(
    target_date = target_date,
    cutoff_price = last_price_hist,
    p_min = p_min, p_max = p_max,
    range_width_pct = (p_max - p_min) / last_price_hist,
    actual_price = actual_price,
    inside_range = inside,
    prob_calm = pred_prob_now[1],
    prob_stress = pred_prob_now[2]
  ))
}

cat("\n=== Empirical coverage ===\n")
coverage_rate <- mean(results$inside_range)
n_obs <- nrow(results)
cat(sprintf("Empirical coverage: %d / %d = %.1f%% (nominal target: 95%%)\n",
            sum(results$inside_range), n_obs, coverage_rate * 100))

# Simple binomial check: under H0 (true 95% coverage), how many breaches
# would be "normal" vs how many we actually saw.
n_breaches <- sum(!results$inside_range)
expected_breaches <- n_obs * 0.05
cat(sprintf("Breaches observed: %d. Expected under nominal 95%%: ~%.1f\n",
            n_breaches, expected_breaches))
binom_test <- binom.test(n_breaches, n_obs, p = 0.05)
cat(sprintf("Binomial test p-value (H0: true breach rate = 5%%): %.4f\n", binom_test$p.value))

write.csv(results, "../data/processed/covid_robustness_result.csv", row.names = FALSE)
write.csv(fan_data, "../data/processed/covid_robustness_fan_data.csv", row.names = FALSE)
cat("\nSaved to covid_robustness_result.csv and covid_robustness_fan_data.csv\n")
