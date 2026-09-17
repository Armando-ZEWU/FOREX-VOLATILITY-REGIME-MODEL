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

cat("Loaded", length(par), "fitted parameters and", length(returns), "observations.\n")

# ---- 2. Current regime probabilities (context for the forecast) ----
# SPEC-dispatched method: State(object, par, data, ...) -- argument name is `data`.
state_probs_obj <- State(object = spec, par = par, data = returns)
pred_prob_now <- state_probs_obj$PredProb[dim(state_probs_obj$PredProb)[1], 1, ]
cat("\n=== Current regime probabilities (as of the last observation) ===\n")
print(pred_prob_now)

# ---- 3. One-step-ahead forecast (95% interval, as decided) ----
# METHODOLOGICAL CHOICE: predict() with do.return.draw=TRUE simulates from
# the FULL predictive distribution, which already properly weights both
# regimes by their current predicted probability (pred_prob_now above) --
# the operationally correct approach, since the model treats the current
# regime as uncertain (a probability), not a known fact. We deliberately
# do NOT force an artificial "assume we are certainly in regime k"
# forecast, which would misrepresent the genuine uncertainty the model
# itself carries.
#
# SPEC-dispatched method: predict(object, newdata=NULL, ..., par=NULL, ...)
# -- argument name is `newdata`, NOT `data` (unlike State() above).

set.seed(42)
confidence_level <- 0.95  # as decided: 95%, the standard choice
alpha_tail <- (1 - confidence_level) / 2  # 0.025 on each side

cat("\nGenerating 1-step-ahead forecast (simulated draws from full predictive distribution)...\n")
forecast_1step <- predict(
  object = spec,
  par = par,
  newdata = returns,
  nahead = 1L,
  do.return.draw = TRUE
)

cat("\n=== Structure of predict() output (inspect before trusting extraction below) ===\n")
str(forecast_1step)

tryCatch({
  draws <- forecast_1step$draw  # ADJUST field name if str() above shows otherwise
  q_low <- quantile(draws, probs = alpha_tail)
  q_high <- quantile(draws, probs = 1 - alpha_tail)
  vol_forecast <- forecast_1step$vol
  
  cat("\n=== 1-step-ahead forecast (log-return %, matching features.py's x100 scale) ===\n")
  cat("Volatility forecast (model-implied, regime-weighted):", vol_forecast, "\n")
  cat(sprintf("%.0f%% interval: [%.4f, %.4f]\n", confidence_level * 100, q_low, q_high))
  
  forecast_output <- data.frame(
    last_date = tail(dates, 1),
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
  cat("\nERROR extracting forecast -- structure differs from assumed.\n")
  cat("Error message:", conditionMessage(e), "\n")
  cat("Check the str() output above and adjust the field names manually.\n")
})