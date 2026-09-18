# ms_garch_forecast.R
# One-step-ahead forecast from the fitted MS-GARCH(K=2) model (ms_garch.R),
# producing the inputs for the project's price-range deliverable
# (methodology.md, objective (b)).
#
# Deliberately kept as a SEPARATE script from ms_garch.R: fitting the
# model and forecasting from it are two distinct stages, following the
# project's established convention of one file per stage (see e.g.
# regression.py vs control_regression.py vs magnitude_regression.py).
#
# FIX (post-mortem, see chat): the original version of this script did
# `fit <- readRDS("ms_garch_fit.rds")` and then called State(fit) /
# predict(fit) directly. That crashes with:
#   Error in .External(list(name = "CppMethod__invoke_notvoid", ...)) :
#     NULL value passed as symbol address
# Root cause: MSGARCH is implemented in C++ via Rcpp (see docs/ms_garch.md,
# section 1). fit$spec is an MSGARCH_SPEC object that wraps a compiled C++
# module through an external pointer. saveRDS() serializes the R-level
# wrapper but NOT the underlying C++ memory it points to -- on reload in a
# new R session, that pointer is a dead reference (looks intact, is not).
# Any call that redescends into the C++ layer (State(), predict(),
# PredPdf(), Volatility(), simulate() on the fit object) then fails this
# way. fit$par (numeric vector), fit$loglik, and fit$Inference$MatCoef are
# plain R objects with no external pointer -- they DO survive
# saveRDS/readRDS without issue.
#
# Fix applied here: ms_garch.R now saves only fit$par (+ loglik + MatCoef)
# to ms_garch_par.rds, not the fit/spec object. This script recreates a
# FRESH MSGARCH_SPEC via CreateSpec() (new, valid C++ pointer) and calls
# the MSGARCH_SPEC-dispatched methods of State() and predict(), passing
# the saved `par` vector explicitly. Per MSGARCH documentation:
#   State(object, par, data, ...)                      -- argument is `data`
#   predict(object, newdata=NULL, ..., par=NULL, ...)   -- argument is `newdata`
# These two are NOT interchangeable -- easy to mix up if you copy one
# call pattern into the other.

library(MSGARCH)

# ---- 1. Recreate the spec (fresh object = valid pointer) and load the estimates ----
# Must be byte-identical to the CreateSpec() call in ms_garch.R -- same
# variance.spec / distribution.spec / switch.spec -- otherwise `par` below
# won't line up with the spec's expected parameter vector.
spec <- CreateSpec(
  variance.spec = list(model = c("sGARCH")),
  distribution.spec = list(distribution = c("std")),
  switch.spec = list(do.mix = FALSE, K = 2)
)

saved <- readRDS("../data/processed/ms_garch_par.rds")
par <- saved$par

# Sanity check before doing anything else: if the names on `par` don't
# match what this spec expects, everything downstream is silently wrong
# rather than cleanly erroring. Check this once, deliberately.
expected_names <- names(CreateSpec(
  variance.spec = list(model = c("sGARCH")),
  distribution.spec = list(distribution = c("std")),
  switch.spec = list(do.mix = FALSE, K = 2)
)$par0)
if (!identical(names(par), expected_names)) {
  cat("\nWARNING: names(par) do not match the spec's expected parameter names.\n")
  cat("Loaded par names:   ", paste(names(par), collapse = ", "), "\n")
  cat("Spec expects names: ", paste(expected_names, collapse = ", "), "\n")
  cat("Stop and check ms_garch.R / ms_garch_par.rds before trusting anything below.\n")
}

data <- read.csv("../data/processed/eurusd_log_returns.csv", stringsAsFactors = FALSE)
returns <- data$log_return
dates <- as.Date(data$Date)

# Also load the raw price series: the last price is needed to convert the
# forecast return interval into an actual price range. Exported in the
# same CSV as the forecast (rather than re-read separately in Python) so
# that price and forecast date are guaranteed consistent by construction --
# if the two files were ever reloaded out of sync, a separately-read price
# could silently belong to a different date than the forecast.
prices_raw <- read.csv("../data/raw/eurusd_daily.csv", stringsAsFactors = FALSE)
prices_raw$Date <- as.Date(prices_raw$Date)
last_forecast_date <- tail(dates, 1)
last_price <- prices_raw$Close[prices_raw$Date == last_forecast_date]

if (length(last_price) != 1) {
  stop(paste("Could not uniquely match the last return date",
             format(last_forecast_date), "to a price in eurusd_daily.csv --",
             "found", length(last_price), "matches. Check that both files",
             "are generated from the same data pull."))
}
cat("Last price (", format(last_forecast_date), "):", last_price, "\n")

cat("Loaded", length(par), "fitted parameters and", length(returns), "observations.\n")

# ---- 2. Current regime probabilities (context for the forecast) ----
# SPEC-dispatched method: State(object, par, data, ...) -- argument name is `data`.
state_probs_obj <- State(object = spec, par = par, data = returns)
pred_prob_now <- state_probs_obj$PredProb[dim(state_probs_obj$PredProb)[1], 1, ]
cat("\n=== Current regime probabilities (as of the last observation) ===\n")
print(pred_prob_now)

# ---- 3. Volatility forecast ----
# SPEC-dispatched method: predict(object, newdata=NULL, ..., par=NULL, ...)
# -- argument name is `newdata`, NOT `data` (unlike State() above).
#
# NOTE: in this version of MSGARCH, predict() returns only $vol (the
# conditional volatility forecast) -- do.return.draw=TRUE did NOT produce
# a $draw element, so quantiles cannot be computed from it (this was
# observed empirically: the earlier version of this script silently
# produced NA bounds because it tried to take quantiles of a non-existent
# $draw field). The interval is therefore obtained from Risk() below,
# which is the package's purpose-built function for predictive-density
# quantiles.
cat("\nGenerating 1-step-ahead volatility forecast...\n")
forecast_1step <- predict(
  object = spec,
  par = par,
  newdata = returns,
  nahead = 1L
)
vol_forecast <- as.numeric(forecast_1step$vol)
cat("Volatility forecast (model-implied, regime-weighted):", vol_forecast, "\n")

# ---- 4. 95% predictive interval via Risk() ----
# METHODOLOGICAL CHOICE: Risk() computes quantiles of the FULL predictive
# density, which already properly weights both regimes by their current
# predicted probability (pred_prob_now above) -- the operationally correct
# approach, since the model treats the current regime as uncertain (a
# probability), not a known fact. We deliberately do NOT force an
# artificial "assume we are certainly in regime k" forecast, which would
# misrepresent the genuine uncertainty the model itself carries.
#
# CONVENTION WARNING: Risk()'s `alpha` argument gives LEFT-TAIL levels
# (Value-at-Risk levels), not a two-sided confidence level. For a
# two-sided 95% interval we therefore need alpha = c(0.025, 0.975):
# the 2.5% quantile is the lower bound, the 97.5% quantile the upper.
# Passing alpha = 0.05 alone would give a one-sided 5% VaR, NOT a 95%
# interval -- an easy and consequential mistake.
#
# SPEC-dispatched method: Risk(object, par, data, alpha, nahead, ...)
# -- argument name is `data` here (like State(), unlike predict()).

set.seed(42)
confidence_level <- 0.95  # as decided: 95%, the standard choice
alpha_lower <- (1 - confidence_level) / 2   # 0.025
alpha_upper <- 1 - alpha_lower              # 0.975

cat("\nComputing 95% predictive interval via Risk()...\n")
risk_obj <- Risk(
  object = spec,
  par = par,
  data = returns,
  alpha = c(alpha_lower, alpha_upper),
  nahead = 1L,
  do.es = FALSE,
  do.its = FALSE
)

cat("\n=== Structure of Risk() output (inspect before trusting extraction below) ===\n")
str(risk_obj)

tryCatch({
  # VaR is a matrix of size nahead x R (here 1 x 2), columns in the order
  # of the alpha vector passed above.
  var_values <- as.numeric(risk_obj$VaR)
  q_low <- var_values[1]   # 2.5% quantile -> lower bound
  q_high <- var_values[2]  # 97.5% quantile -> upper bound
  
  cat("\n=== 1-step-ahead forecast (log-return %, matching features.py's x100 scale) ===\n")
  cat("Volatility forecast:", vol_forecast, "\n")
  cat(sprintf("%.0f%% interval: [%.4f, %.4f]\n", confidence_level * 100, q_low, q_high))
  
  # Sanity check: the interval must bracket zero and be correctly ordered,
  # otherwise the alpha convention was misread (see CONVENTION WARNING).
  if (q_low >= q_high) {
    cat("\nWARNING: lower bound >= upper bound -- check the alpha convention\n")
    cat("and the column ordering of risk_obj$VaR before using these numbers.\n")
  }
  
  forecast_output <- data.frame(
    last_date = last_forecast_date,
    last_price = last_price,
    confidence_level = confidence_level,
    return_q_low = q_low,
    return_q_high = q_high,
    vol_forecast = vol_forecast,
    prob_regime_1_current = pred_prob_now[1],
    prob_regime_2_current = pred_prob_now[2]
  )
  write.csv(forecast_output, "../data/processed/ms_garch_price_range_inputs.csv", row.names = FALSE)
  cat("\nForecast inputs saved to ms_garch_price_range_inputs.csv --\n")
  cat("to be converted into an actual EUR/USD price range in Python (price_range.py).\n")
}, error = function(e) {
  cat("\nERROR extracting risk quantiles -- structure differs from assumed.\n")
  cat("Error message:", conditionMessage(e), "\n")
  cat("Check the str() output above and adjust the extraction manually.\n")
})

# ---- 5. Multi-level predictive intervals for the fan chart ----
# Central-bank-style fan chart (Bank of England convention): several
# nested confidence bands rather than a single interval, to show how the
# range narrows toward the center vs. widens toward the tails.
#
# Levels revised from an initial proposal of 5/15/20/30/60/80/95% (which
# would have produced a near-invisible 5% band and two nearly
# indistinguishable 15%/20% bands) to four well-separated levels, each
# visually distinct on the resulting chart.
confidence_levels <- c(0.20, 0.50, 0.80, 0.95)

# Build the full alpha vector (lower and upper tail for every level),
# passed to Risk() in a single call.
alpha_pairs <- lapply(confidence_levels, function(cl) {
  a_low <- (1 - cl) / 2
  a_high <- 1 - a_low
  c(a_low, a_high)
})
alpha_vector <- sort(unique(unlist(alpha_pairs)))
cat("\nAlpha levels requested from Risk():", paste(alpha_vector, collapse=", "), "\n")

risk_multi <- Risk(
  object = spec,
  par = par,
  data = returns,
  alpha = alpha_vector,
  nahead = 1L,
  do.es = FALSE,
  do.its = FALSE
)

cat("\n=== Structure of multi-level Risk() output ===\n")
str(risk_multi)

tryCatch({
  var_row <- as.numeric(risk_multi$VaR[1, ])
  names(var_row) <- alpha_vector
  
  fan_rows <- lapply(confidence_levels, function(cl) {
    a_low <- (1 - cl) / 2
    a_high <- 1 - a_low
    data.frame(
      confidence_level = cl,
      alpha_low = a_low,
      alpha_high = a_high,
      return_q_low = var_row[as.character(a_low)],
      return_q_high = var_row[as.character(a_high)]
    )
  })
  fan_df <- do.call(rbind, fan_rows)
  fan_df$last_date <- last_forecast_date
  fan_df$last_price <- last_price
  
  write.csv(fan_df, "../data/processed/ms_garch_fan_chart_inputs.csv", row.names = FALSE)
  cat("\nFan chart inputs saved to ms_garch_fan_chart_inputs.csv\n")
  print(fan_df)
}, error = function(e) {
  cat("\nERROR building fan chart data -- check risk_multi's structure above.\n")
  cat("Error message:", conditionMessage(e), "\n")
})

# ---- 6. TRUE regime-conditional one-step-ahead forecast ----
# CORRECTION to docs/ms_garch.md section 1: that document cited Gray
# (1996)'s "collapsing" approximation and an "infinite path dependency"
# problem as the reason a per-regime forecast was hard to obtain. On
# checking the literature directly, this was based on a misidentification
# of which MS-GARCH variant the MSGARCH package's Markov-switching option
# actually implements. Per the package's own documentation, it implements
# Haas, Mittnik & Paolella (2004a), NOT Gray (1996) -- and Haas et al.'s
# specification has NO path-dependency problem: each regime maintains its
# own independent variance recursion based on observed data, computable
# directly. This section does exactly that, replacing the "illustrative
# only, approximate" regime comparison previously used in price_range.py.
#
# Recursion: sigma_k^2(t) = omega_k + alpha_k * r(t-1)^2 + beta_k * sigma_k^2(t-1)
# run independently for k=1 and k=2 over the SAME observed return series.
# Initialized at each regime's own unconditional (long-run) variance.

cat("\n=== TRUE regime-conditional forecast (Haas et al. 2004a recursion) ===\n")

omega_1 <- par["alpha0_1"]; alpha_1 <- par["alpha1_1"]; beta_1 <- par["beta_1"]; nu_1 <- par["nu_1"]
omega_2 <- par["alpha0_2"]; alpha_2 <- par["alpha1_2"]; beta_2 <- par["beta_2"]; nu_2 <- par["nu_2"]

cat(sprintf("Regime 1: omega=%.6f alpha=%.4f beta=%.4f nu=%.3f\n", omega_1, alpha_1, beta_1, nu_1))
cat(sprintf("Regime 2: omega=%.6f alpha=%.4f beta=%.4f nu=%.3f\n", omega_2, alpha_2, beta_2, nu_2))

Tn <- length(returns)
sigma2_1 <- numeric(Tn)
sigma2_2 <- numeric(Tn)
sigma2_1[1] <- omega_1 / (1 - alpha_1 - beta_1)
sigma2_2[1] <- omega_2 / (1 - alpha_2 - beta_2)

for (t in 2:Tn) {
  sigma2_1[t] <- omega_1 + alpha_1 * returns[t-1]^2 + beta_1 * sigma2_1[t-1]
  sigma2_2[t] <- omega_2 + alpha_2 * returns[t-1]^2 + beta_2 * sigma2_2[t-1]
}

# One-step-ahead forecast (t = T+1) for each regime
sigma2_1_next <- omega_1 + alpha_1 * returns[Tn]^2 + beta_1 * sigma2_1[Tn]
sigma2_2_next <- omega_2 + alpha_2 * returns[Tn]^2 + beta_2 * sigma2_2[Tn]
sigma_1_next <- sqrt(sigma2_1_next)
sigma_2_next <- sqrt(sigma2_2_next)

cat(sprintf("\nOne-step-ahead volatility forecast if regime 1 (calm): %.4f\n", sigma_1_next))
cat(sprintf("One-step-ahead volatility forecast if regime 2 (stress): %.4f\n", sigma_2_next))

# Regime-specific Student's t quantiles (standardized to unit variance:
# raw Student's t has variance nu/(nu-2), so scale by sqrt((nu-2)/nu))
std_t_quantile <- function(p, nu) qt(p, df = nu) * sqrt((nu - 2) / nu)

regime_forecast <- data.frame()
for (cl in confidence_levels) {
  a_low <- (1 - cl) / 2
  a_high <- 1 - a_low
  regime_forecast <- rbind(regime_forecast, data.frame(
    confidence_level = cl,
    regime = "1_calm",
    return_q_low = std_t_quantile(a_low, nu_1) * sigma_1_next,
    return_q_high = std_t_quantile(a_high, nu_1) * sigma_1_next
  ))
  regime_forecast <- rbind(regime_forecast, data.frame(
    confidence_level = cl,
    regime = "2_stress",
    return_q_low = std_t_quantile(a_low, nu_2) * sigma_2_next,
    return_q_high = std_t_quantile(a_high, nu_2) * sigma_2_next
  ))
}
regime_forecast$last_date <- last_forecast_date
regime_forecast$last_price <- last_price
write.csv(regime_forecast, "../data/processed/ms_garch_regime_conditional_forecast.csv", row.names = FALSE)
print(regime_forecast)

# ---- VALIDATION: does mixing these two regime-conditional forecasts,
# weighted by current regime probabilities, approximately reproduce the
# already-obtained Risk() mixture result? This cross-checks the manual
# recursion above WITHOUT relying on any unverified assumption about
# internal package objects -- if it matches, the recursion is confirmed
# correct by an independent route. ----
w1 <- as.numeric(pred_prob_now[1])
w2 <- as.numeric(pred_prob_now[2])
mixed_vol_approx <- sqrt(w1 * sigma2_1_next + w2 * sigma2_2_next)
cat(sprintf("\nValidation check: weighted-average implied vol = %.4f\n", mixed_vol_approx))
cat(sprintf("(compare to Risk()-based vol_forecast reported earlier: %.4f)\n", vol_forecast))
cat("These won't match exactly (mixing variances isn't the same as mixing\n")
cat("full quantile distributions), but should be in the same ballpark --\n")
cat("a large discrepancy would indicate an error in the manual recursion.\n")