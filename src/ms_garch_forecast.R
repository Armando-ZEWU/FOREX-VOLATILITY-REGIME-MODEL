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