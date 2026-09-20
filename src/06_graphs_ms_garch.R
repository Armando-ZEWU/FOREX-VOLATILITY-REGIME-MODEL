# ==============================================================================
# Graphs — Markov-Switching_Garch.md
# Génère les 6 figures retenues pour le document MS-GARCH (K=2)
# (+ 1 figure de diagnostic optionnelle, désactivée par défaut)
# Sortie : PNG, 300 dpi, dans graphs/Markov-Switching_GARCH_plot/
#
# Entrées (data/processed/) :
#   ms_garch_regime_probs.csv        Date, log_return, prob_regime_1, prob_regime_2
#   ms_garch_transition_matrix.csv   matrice 2x2 de transition
#   eurusd_garch_shocks.csv          GARCH(1,1) Student-t à régime unique
#
# CE QUI EST RECONSTRUIT (et pourquoi) :
#   Les CSV ne contiennent que les probabilités LISSÉES. Ni sigma_k(t) par
#   régime, ni le chemin de Viterbi n'ont été exportés. Le script les
#   reconstruit à partir des paramètres publiés en §4.1 du document
#   (récursion GARCH parallèle de Haas, Mittnik & Paolella 2004a).
#   -> Lire le bloc "CONTRÔLE DE RECONSTRUCTION" imprimé dans la console
#      AVANT d'utiliser les figures 2, 3 et 5.
#
# Mapping figure -> section du document :
#   01  §4.2, §6      probabilité lissée du régime de stress
#   02  §4.2          sigma_k(t) par régime, sigma de long terme
#   03  §5            MS-GARCH (mélange) vs GARCH à régime unique
#   04  §6.1          zoom COVID (tableau 9% -> 99,998%)
#   05  §6.2          part annuelle en stress : trois mesures
#   06  §5            écarts AIC / BIC / -LogLik
#   07  (optionnel)   demi-vie vs alpha+beta — absent du document
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

PLOT_DIAGNOSTIC <- FALSE   # TRUE -> génère aussi la figure 07

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Markov-Switching_GARCH_plot")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

theme_set(
  theme_bw(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 13),
      panel.grid.minor = element_blank()
    )
)

save_fig <- function(plot, filename, width = 7, height = 4.5) {
  ggsave(file.path(output_dir, filename), plot,
         width = width, height = height, dpi = 300, units = "in", bg = "white")
}

col_r1 <- "steelblue4"   # régime 1 : calme
col_r2 <- "firebrick"    # régime 2 : stress
pal_regime <- c("Régime 1 (calme)" = col_r1, "Régime 2 (stress)" = col_r2)

# ---- 1. Chargement des données -------------------------------------------
probs <- read_csv(file.path(processed_dir, "ms_garch_regime_probs.csv"),
                  col_types = cols(Date = col_date(), log_return = col_double(),
                                   prob_regime_1 = col_double(),
                                   prob_regime_2 = col_double()))

trans_raw <- read_csv(file.path(processed_dir, "ms_garch_transition_matrix.csv"),
                      show_col_types = FALSE)

shocks <- read_csv(file.path(processed_dir, "eurusd_garch_shocks.csv"),
                   col_types = cols(Date = col_date(),
                                    conditional_volatility = col_double(),
                                    residual = col_double(),
                                    standardized_residual = col_double()))

# ---- 2. Paramètres publiés (§4.1 du document) -----------------------------
par_ms <- tibble(
  label = c("Régime 1 (calme)", "Régime 2 (stress)"),
  omega = c(0.0001241, 0.0057432),
  alpha = c(0.0106220, 0.0090000),
  beta  = c(0.9864591, 0.9802132),
  nu    = c(7.0711,    22.0046),
  se_alpha = c(0.0077169, 0.0132647),
  se_beta  = c(0.0013367, 0.0083909)
) %>%
  mutate(persistence = alpha + beta,
         half_life   = log(0.5) / log(persistence),
         sigma_lr    = sqrt(omega / (1 - persistence)))

# Matrice de transition : colonnes 2 et 3 du CSV (la colonne 1 = étiquettes)
P <- as.matrix(trans_raw[, 2:3])
dimnames(P) <- list(c("1", "2"), c("1", "2"))
stationary <- c(P[2, 1], P[1, 2]) / (P[1, 2] + P[2, 1])
duration   <- 1 / (1 - diag(P))

# ---- 3. Reconstruction : sigma_k(t) et chemin de Viterbi -------------------
garch_path <- function(r, omega, alpha, beta) {
  n  <- length(r)
  s2 <- numeric(n)
  s2[1] <- omega / (1 - alpha - beta)      # init. variance de long terme
  for (t in 2:n) s2[t] <- omega + alpha * r[t - 1]^2 + beta * s2[t - 1]
  sqrt(s2)
}

# Densité Student-t standardisée (variance 1), cohérente avec "std" de MSGARCH
dstd <- function(x, nu) {
  s <- sqrt(nu / (nu - 2))
  dt(x * s, df = nu) * s
}

viterbi_path <- function(r, sigma_mat, nu_vec, P, pi0) {
  n <- length(r); K <- ncol(sigma_mat)
  logf <- matrix(NA_real_, n, K)
  for (k in 1:K) logf[, k] <- log(dstd(r / sigma_mat[, k], nu_vec[k]) / sigma_mat[, k])
  logP  <- log(P)
  delta <- matrix(-Inf, n, K)
  psi   <- matrix(NA_integer_, n, K)
  delta[1, ] <- log(pi0) + logf[1, ]
  for (t in 2:n) for (k in 1:K) {
    cand        <- delta[t - 1, ] + logP[, k]
    psi[t, k]   <- which.max(cand)
    delta[t, k] <- max(cand) + logf[t, k]
  }
  path <- integer(n)
  path[n] <- which.max(delta[n, ])
  for (t in (n - 1):1) path[t] <- psi[t + 1, path[t + 1]]
  path
}

vol <- probs %>%
  mutate(sigma_1 = garch_path(log_return, par_ms$omega[1], par_ms$alpha[1], par_ms$beta[1]),
         sigma_2 = garch_path(log_return, par_ms$omega[2], par_ms$alpha[2], par_ms$beta[2]),
         # mélange pondéré par les probabilités LISSÉES : description in-sample
         sigma_mix = sqrt(prob_regime_1 * sigma_1^2 + prob_regime_2 * sigma_2^2))

vol$viterbi <- viterbi_path(vol$log_return, cbind(vol$sigma_1, vol$sigma_2),
                            par_ms$nu, P, stationary)

# ---- 4. CONTRÔLE DE RECONSTRUCTION (s'imprime dans la console R) ----------
check <- function(label, got, doc, tol) {
  ok <- all(abs(got - doc) <= tol)
  cat(sprintf("%-38s obtenu: %-18s doc: %-18s [%s]\n", label,
              paste(round(got, 3), collapse = " / "),
              paste(doc, collapse = " / "),
              if (ok) "OK" else "ÉCART"))
  ok
}

cat("\n================ CONTRÔLE DE RECONSTRUCTION ================\n")
res <- c(
  check("Demi-vies (jours)",           par_ms$half_life, c(237.1, 63.9), 0.15),
  check("Sigma long terme",            par_ms$sigma_lr,  c(0.206, 0.730), 0.002),
  check("Probabilités stationnaires",  stationary,       c(0.717, 0.283), 0.001),
  check("Durées Markov 1/(1-P) (j)",   unname(duration), c(404, 160),     1)
)
cat("\n-- Informatif (pas de tolérance stricte) --\n")
n2020 <- sum(vol$viterbi == 2 & format(vol$Date, "%Y") == "2020")
cat("Jours 2020 en régime 2, Viterbi reconstruit :", n2020,
    "sur", sum(format(vol$Date, "%Y") == "2020"), "(doc : 36 sur 249)\n")
cat("Jours 2020 avec P(régime 2) > 50% (lissé)   :",
    sum(vol$prob_regime_2 > 0.5 & format(vol$Date, "%Y") == "2020"), "\n")
cat("Accord Viterbi reconstruit vs lissé > 50%   :",
    percent(mean((vol$viterbi == 2) == (vol$prob_regime_2 > 0.5)), accuracy = 0.1), "\n")
cat("Part du temps en régime 2 (Viterbi)         :",
    percent(mean(vol$viterbi == 2), accuracy = 0.1), "(doc : 28,3% stationnaire)\n")
if (all(res)) {
  cat("\n=> Contrôle stationnaire/paramètres OK : la reconstruction est cohérente.\n")
} else {
  cat("\n=> ATTENTION : au moins un écart. Ne pas utiliser les figures 02, 03, 05.\n")
}
cat("=============================================================\n\n")

# ==============================================================================
# FIGURE 01 — Probabilité lissée du régime de stress (§4.2, §6)
# ==============================================================================
g1 <- ggplot(vol, aes(x = Date, y = prob_regime_2)) +
  geom_area(fill = col_r2, alpha = 0.35) +
  geom_line(color = col_r2, linewidth = 0.25) +
  geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey40") +
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0, 1)) +
  labs(title = "Probabilité lissée du régime de stress (régime 2), 2010-2026",
       subtitle = "Ligne pointillée : seuil de 50%",
       x = NULL, y = "P(régime 2)")
save_fig(g1, "01_smoothed_prob_regime2.png")

# ==============================================================================
# FIGURE 02 — Volatilité conditionnelle par régime (§4.2)
# ==============================================================================
vol_long <- vol %>%
  select(Date, sigma_1, sigma_2) %>%
  pivot_longer(-Date, names_to = "regime", values_to = "sigma") %>%
  mutate(regime = recode(regime, sigma_1 = "Régime 1 (calme)",
                                 sigma_2 = "Régime 2 (stress)"))

g2 <- ggplot(vol_long, aes(x = Date, y = sigma, color = regime)) +
  geom_line(linewidth = 0.3) +
  geom_hline(data = par_ms, aes(yintercept = sigma_lr, color = label),
             linetype = "dashed", linewidth = 0.5) +
  scale_color_manual(values = pal_regime) +
  labs(title = "Volatilité conditionnelle par régime",
       subtitle = "Pointillés : \u03c3 de long terme (0,206 et 0,730)",
       x = NULL, y = "\u03c3(t) (%)", color = NULL) +
  theme(legend.position = "bottom")
save_fig(g2, "02_conditional_volatility_by_regime.png")

# ==============================================================================
# FIGURE 03 — MS-GARCH (mélange) vs GARCH à régime unique (§5)
# ==============================================================================
cmp <- vol %>%
  inner_join(select(shocks, Date, sigma_single = conditional_volatility), by = "Date") %>%
  select(Date, sigma_mix, sigma_single) %>%
  pivot_longer(-Date, names_to = "modele", values_to = "sigma") %>%
  mutate(modele = recode(modele,
                         sigma_mix    = "MS-GARCH (mélange pondéré, K=2)",
                         sigma_single = "GARCH(1,1) Student-t, régime unique"))

g3 <- ggplot(cmp, aes(x = Date, y = sigma, color = modele)) +
  geom_line(linewidth = 0.3) +
  scale_color_manual(values = c("MS-GARCH (mélange pondéré, K=2)" = "firebrick",
                                "GARCH(1,1) Student-t, régime unique" = "grey45")) +
  labs(title = "MS-GARCH vs GARCH à régime unique \u2014 volatilité conditionnelle",
       subtitle = "Mélange pondéré par les probabilités lissées (description in-sample)",
       x = NULL, y = "\u03c3(t) (%)", color = NULL) +
  theme(legend.position = "bottom")
save_fig(g3, "03_msgarch_vs_single_regime.png")

# ==============================================================================
# FIGURE 04 — Zoom COVID (§6.1, tableau du document)
# ==============================================================================
covid <- vol %>% filter(Date >= as.Date("2020-01-02"), Date <= as.Date("2020-06-30"))
covid_pts <- covid %>%
  filter(Date %in% as.Date(c("2020-02-18", "2020-02-25", "2020-03-11", "2020-04-17")))

g4 <- ggplot(covid, aes(x = Date, y = prob_regime_2)) +
  geom_area(fill = col_r2, alpha = 0.3) +
  geom_line(color = col_r2, linewidth = 0.6) +
  geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey40") +
  geom_point(data = covid_pts, size = 2, color = "grey10") +
  geom_text(data = covid_pts,
            aes(label = paste0(format(Date, "%d/%m"), " : ",
                               percent(prob_regime_2, accuracy = 0.1))),
            hjust = -0.1, vjust = -0.7, size = 3, color = "grey10") +
  scale_y_continuous(labels = percent_format(accuracy = 1),
                     limits = c(0, 1.12), breaks = seq(0, 1, 0.25)) +
  scale_x_date(date_labels = "%b %Y", date_breaks = "1 month") +
  labs(title = "Probabilité lissée du régime de stress \u2014 COVID-19, janvier-juin 2020",
       x = NULL, y = "P(régime 2)")
save_fig(g4, "04_covid_detection_zoom.png")

# ==============================================================================
# FIGURE 05 — Part annuelle en régime de stress : trois mesures (§6.2)
# ==============================================================================
annual <- vol %>%
  mutate(year = as.integer(format(Date, "%Y"))) %>%
  group_by(year) %>%
  summarise(`Viterbi (reconstruit)` = mean(viterbi == 2),
            `Lissé > 50%`           = mean(prob_regime_2 > 0.5),
            `Probabilité moyenne`   = mean(prob_regime_2), .groups = "drop") %>%
  pivot_longer(-year, names_to = "mesure", values_to = "part") %>%
  mutate(mesure = factor(mesure, levels = c("Viterbi (reconstruit)", "Lissé > 50%",
                                            "Probabilité moyenne")))

g5 <- ggplot(annual, aes(x = factor(year), y = part, fill = mesure)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.72) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_fill_manual(values = c("Viterbi (reconstruit)" = "grey35",
                               "Lissé > 50%"           = col_r2,
                               "Probabilité moyenne"   = "darkorange2")) +
  labs(title = "Part annuelle en régime de stress selon trois mesures",
       x = NULL, y = "Part de l'année", fill = NULL) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))
save_fig(g5, "05_annual_regime_share.png")

# ==============================================================================
# FIGURE 06 — Écarts AIC / BIC / -LogLik au meilleur modèle (§5)
#   Écarts (dot plot), pas de barres depuis zéro : ~13 points sur ~5 600.
# ==============================================================================
crit <- tibble(
  modele   = rep(c("GARCH(1,1) Student-t", "MS-GARCH (K=2)"), 3),
  metrique = rep(c("AIC", "BIC", "-Log-vraisemblance"), each = 2),
  valeur   = c(5646.78, 5633.27,
               5678.46, 5696.64,
               2818.39, 2806.64)
) %>%
  group_by(metrique) %>%
  mutate(delta = valeur - min(valeur)) %>%
  ungroup() %>%
  mutate(metrique = factor(metrique, levels = c("AIC", "BIC", "-Log-vraisemblance")))

g6 <- ggplot(crit, aes(x = delta, y = fct_rev(metrique), color = modele)) +
  geom_line(aes(group = metrique), color = "grey65", linewidth = 0.5) +
  geom_point(size = 3.2) +
  geom_text(aes(label = ifelse(delta > 0, paste0("+", number(delta, accuracy = 0.01)), "0")),
            vjust = -1.1, size = 3, show.legend = FALSE) +
  scale_color_manual(values = c("GARCH(1,1) Student-t" = "grey40",
                                "MS-GARCH (K=2)" = "firebrick")) +
  expand_limits(x = c(-1, 21)) +
  labs(title = "Écart au meilleur modèle sur chaque critère (0 = meilleur)",
       subtitle = "Plus bas = meilleur. AIC et BIC ne désignent pas le même modèle.",
       x = "\u0394 par rapport au meilleur", y = NULL, color = NULL) +
  theme(legend.position = "bottom")
save_fig(g6, "06_information_criteria_delta.png", height = 3.6)

# ==============================================================================
# FIGURE 07 (OPTIONNELLE) — Demi-vie vs alpha+beta
#   Absente du document. IC : SE(alpha+beta) calculée SANS la covariance
#   Cov(alpha,beta) (non exportée) -> IC probablement trop large.
# ==============================================================================
if (PLOT_DIAGNOSTIC) {
  curve_df <- tibble(p = seq(0.960, 0.9996, length.out = 3000)) %>%
    mutate(hl = log(0.5) / log(p))
  pts <- par_ms %>%
    mutate(se = sqrt(se_alpha^2 + se_beta^2),
           lo = persistence - 1.96 * se,
           hi = pmin(persistence + 1.96 * se, 0.99985),
           hl_lo = log(0.5) / log(lo), hl_hi = log(0.5) / log(hi))

  g7 <- ggplot(curve_df, aes(x = p, y = hl)) +
    geom_line(color = "grey30", linewidth = 0.7) +
    geom_segment(data = pts, inherit.aes = FALSE,
                 aes(x = lo, xend = hi, y = half_life, yend = half_life, color = label),
                 linewidth = 1) +
    geom_point(data = pts, inherit.aes = FALSE,
               aes(x = persistence, y = half_life, color = label), size = 2.8) +
    scale_y_log10(labels = label_number(accuracy = 1),
                  breaks = c(10, 30, 100, 300, 1000, 4000)) +
    scale_color_manual(values = pal_regime) +
    labs(title = "Demi-vie du choc en fonction de \u03b1+\u03b2 (échelle log)",
         x = "\u03b1 + \u03b2", y = "Demi-vie (jours)", color = NULL) +
    theme(legend.position = "bottom")
  save_fig(g7, "07_halflife_vs_persistence.png")
}

# ==============================================================================
cat("Terminé \u2014", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")
