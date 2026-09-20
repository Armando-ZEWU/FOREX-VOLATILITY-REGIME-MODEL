# ==============================================================================
# Graphs — GARCH_1_1.md
# Génère les 9 figures identifiées pour le document GARCH_1_1.md
# Sortie : PNG, 300 dpi, dans ./graphs_output/
#
# IMPORTANT (lire avant d'exécuter) :
#   - eurusd_garch_shocks.csv ne contient QUE le modèle retenu (Student-t).
#     Le modèle Normal (§4-5 du doc) n'a jamais été sauvegardé séparément.
#   - Ce script reconstruit donc la volatilité conditionnelle et les résidus
#     standardisés du modèle NORMAL par récursion GARCH(1,1) manuelle, en
#     utilisant les paramètres publiés dans GARCH_1_1.md (section 4).
#   - Vérification effectuée hors-R (Python) avant d'écrire ce script :
#     la reconstruction reproduit à l'identique les diagnostics du document
#     (kurtosis excédentaire 1.618 vs 1.620 publié, range std résiduel
#     [-5.90, 5.01] vs [-5.91, 5.02] publié). Écart négligeable, cohérent
#     avec l'arrondi des paramètres publiés à 4-5 décimales.
#   - Le modèle Student-t, lui, utilise directement standardized_residual
#     et conditional_volatility de eurusd_garch_shocks.csv (donnée réelle,
#     pas une reconstruction).
# ==============================================================================

library(tidyverse)
library(scales)

# ---- 0. Chemins ---------------------------------------------------------
# Architecture du projet (cohérente avec GARCH_1_1.md section 11) :
#   src/            <- ce script
#   data/raw/       <- eurusd_daily.csv
#   data/processed/ <- eurusd_log_returns.csv, eurusd_garch_shocks.csv
#   graphs/GARCH_1_1/ <- PNG produits ici
#
# On utilise `here` plutôt qu'un chemin relatif ou absolu : here() détecte la
# racine du projet automatiquement (via le dossier .git, puisque le repo est
# sur GitHub) et construit les chemins depuis cette racine — peu importe le
# working directory courant au moment du source(). Ça règle définitivement
# le bug rencontré précédemment (source() ne change pas le working directory).
#
# Installation si besoin : install.packages("here")
library(here)

raw_dir       <- here("data", "raw")
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "GARCH_1_1")
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

# ---- 1. Chargement des données -------------------------------------------
daily  <- read_csv(file.path(raw_dir, "eurusd_daily.csv"),
                   col_types = cols(Date = col_date(), Close = col_double()))

returns <- read_csv(file.path(processed_dir, "eurusd_log_returns.csv"),
                    col_types = cols(Date = col_date(), log_return = col_double()))

shocks <- read_csv(file.path(processed_dir, "eurusd_garch_shocks.csv"),
                   col_types = cols(Date = col_date(), conditional_volatility = col_double(),
                                    residual = col_double(), standardized_residual = col_double()))

# ---- 2. Reconstruction du modèle Normal (paramètres §4 de GARCH_1_1.md) --
garch11_recursion <- function(r, mu, omega, alpha, beta) {
  n <- length(r)
  eps <- r - mu
  sigma2 <- numeric(n)
  sigma2[1] <- var(eps)                      # initialisation par la variance d'échantillon
  for (t in 2:n) {
    sigma2[t] <- omega + alpha * eps[t - 1]^2 + beta * sigma2[t - 1]
  }
  sigma <- sqrt(sigma2)
  z <- eps / sigma
  tibble(sigma = sigma, standardized_residual = z)
}

# Paramètres Normal — GARCH_1_1.md section 4
mu_n <- -0.00588; omega_n <- 0.001446; alpha_n <- 0.0350; beta_n <- 0.9595

normal_fit <- garch11_recursion(returns$log_return, mu_n, omega_n, alpha_n, beta_n)
returns_normal <- returns %>%
  mutate(sigma_normal = normal_fit$sigma,
         z_normal = normal_fit$standardized_residual)

# Jeu fusionné pour les comparaisons Normal vs Student-t
compare_df <- returns_normal %>%
  inner_join(shocks, by = "Date") %>%
  rename(sigma_studentt = conditional_volatility,
         z_studentt = standardized_residual)

nu <- 7.0414   # degrés de liberté du modèle Student-t retenu (§6)

# ==============================================================================
# GRAPH 1 — Série des rendements log EUR/USD
# ==============================================================================
g1 <- ggplot(returns, aes(x = Date, y = log_return)) +
  geom_line(color = "steelblue4", linewidth = 0.25) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  labs(title = "Rendements log journaliers EUR/USD (2010-2026)",
       x = NULL, y = "Rendement log (%)")

save_fig(g1, "01_returns_series.png")

# ==============================================================================
# GRAPH 2 — Histogramme des rendements + densité Normale de comparaison
# ==============================================================================
mu_emp  <- mean(returns$log_return)
sd_emp  <- sd(returns$log_return)

g2 <- ggplot(returns, aes(x = log_return)) +
  geom_histogram(aes(y = after_stat(density)), bins = 100,
                 fill = "steelblue3", alpha = 0.6, color = "white", linewidth = 0.1) +
  stat_function(fun = dnorm, args = list(mean = mu_emp, sd = sd_emp),
                color = "firebrick", linewidth = 0.9) +
  labs(title = "Distribution des rendements log vs. Normale ajustée",
       subtitle = str_wrap("Écart visible dans les queues — quantifié formellement en §5.2", width = 65),
       x = "Rendement log (%)", y = "Densité")

save_fig(g2, "02_returns_histogram_vs_normal.png")

# ==============================================================================
# GRAPH 3 — Volatilité conditionnelle : Normal vs Student-t
# ==============================================================================
vol_long <- compare_df %>%
  select(Date, sigma_normal, sigma_studentt) %>%
  pivot_longer(-Date, names_to = "modele", values_to = "sigma") %>%
  mutate(modele = recode(modele, sigma_normal = "Normal", sigma_studentt = "Student-t"))

g3 <- ggplot(vol_long, aes(x = Date, y = sigma, color = modele)) +
  geom_line(linewidth = 0.3) +
  scale_color_manual(values = c("Normal" = "grey50", "Student-t" = "firebrick")) +
  labs(title = "Volatilité conditionnelle estimée — Normal vs Student-t",
       x = NULL, y = "\u03c3(t) (%)", color = "Modèle")

save_fig(g3, "03_conditional_volatility_comparison.png")

# ==============================================================================
# GRAPH 4 — Résidus standardisés du modèle retenu (Student-t)
# ==============================================================================
g4 <- ggplot(shocks, aes(x = Date, y = standardized_residual)) +
  geom_line(color = "darkorange3", linewidth = 0.25) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  labs(title = "Résidus standardisés — GARCH(1,1) Student-t (\u03bd \u2248 7.04)",
       x = NULL, y = "Résidu standardisé")

save_fig(g4, "04_standardized_residuals_studentt.png")

# ==============================================================================
# GRAPH 5 — QQ-plot résidus standardisés (modèle Normal) vs Normale théorique
#           -> montre l'inadéquation qui motive le passage au Student-t (§5.2)
# ==============================================================================
g5 <- ggplot(compare_df, aes(sample = z_normal)) +
  stat_qq(color = "steelblue4", alpha = 0.5, size = 0.8) +
  stat_qq_line(color = "firebrick", linewidth = 0.8) +
  labs(title = "QQ-plot — résidus standardisés (modèle Normal) vs Normale",
       subtitle = str_wrap("Déviation nette dans les queues — motive le passage au Student-t", width = 65),
       x = "Quantiles théoriques (Normale)", y = "Quantiles empiriques")

save_fig(g5, "05_qqplot_normal_model.png")

# ==============================================================================
# GRAPH 6 — QQ-plot résidus standardisés (modèle Student-t retenu)
#           vs Student-t standardisée théorique (\u03bd \u2248 7.04) — §7.1
# ==============================================================================
qstd_t <- function(p, nu) qt(p, df = nu) / sqrt(nu / (nu - 2))  # t standardisée à variance 1

g6 <- ggplot(shocks, aes(sample = standardized_residual)) +
  stat_qq(distribution = qstd_t, dparams = list(nu = nu),
          color = "darkorange3", alpha = 0.5, size = 0.8) +
  stat_qq_line(distribution = qstd_t, dparams = list(nu = nu),
               color = "firebrick", linewidth = 0.8) +
  labs(title = "QQ-plot — résidus standardisés vs Student-t (\u03bd \u2248 7.04)",
       subtitle = str_wrap("Bon ajustement — confirme le choix du modèle retenu", width = 65),
       x = "Quantiles théoriques (Student-t standardisée)", y = "Quantiles empiriques")

save_fig(g6, "06_qqplot_studentt_model.png")

# ==============================================================================
# GRAPH 7 — Comparaison AIC / BIC / -LogLik (valeurs publiées, §7)
# ==============================================================================
model_comparison <- tibble(
  modele = rep(c("Normal", "Student-t"), times = 3),
  metrique = rep(c("AIC", "BIC", "-Log-Vraisemblance"), each = 2),
  valeur = c(5808.34, 5646.78,      # AIC
             5833.69, 5678.46,      # BIC
             2900.17, 2818.39)      # -LogLik (signe inversé pour lecture "plus bas = mieux" partout)
) %>% mutate(metrique = factor(metrique, levels = c("AIC", "BIC", "-Log-Vraisemblance")))

g7 <- ggplot(model_comparison, aes(x = metrique, y = valeur, fill = modele)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6) +
  scale_fill_manual(values = c("Normal" = "grey50", "Student-t" = "firebrick")) +
  labs(title = "Comparaison des critères d'information — Normal vs Student-t",
       subtitle = str_wrap("Plus bas = meilleur ajustement, sur les trois critères", width = 65),
       x = NULL, y = "Valeur", fill = "Modèle")

save_fig(g7, "07_model_comparison_aic_bic.png")

# ==============================================================================
# GRAPH 8 — Kurtosis excédentaire : empirique vs théorique (§7.1)
# ==============================================================================
kurtosis_df <- tibble(
  modele = c("Normal", "Normal", "Student-t", "Student-t"),
  type = c("Empirique", "Théorique (implicite au modèle)",
           "Empirique", "Théorique (implicite au modèle)"),
  valeur = c(1.620, 0,       # Normal : théorique = 0 par définition
             1.831, 1.973)   # Student-t : théorique = 6/(nu-4)
)

g8 <- ggplot(kurtosis_df, aes(x = modele, y = valeur, fill = type)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6) +
  scale_fill_manual(values = c("Empirique" = "steelblue3",
                               "Théorique (implicite au modèle)" = "grey50")) +
  labs(title = "Kurtosis excédentaire — empirique vs théorique",
       subtitle = str_wrap("Student-t : l'empirique (1.831) est proche du théorique (1.973) -> bon ajustement", width = 65),
       x = NULL, y = "Kurtosis excédentaire", fill = NULL)

save_fig(g8, "08_kurtosis_comparison.png")

# ==============================================================================
# GRAPH 9 — Probabilité de la queue (-2.67%) : Normal vs Student-t (§9.3)
#           Échelle log — illustration économique de l'inadéquation du modèle Normal
# ==============================================================================
tail_prob_df <- tibble(
  modele = c("Normal", "Student-t"),
  probabilite = c(1.7e-9, 0.00029)
)

g9 <- ggplot(tail_prob_df, aes(x = modele, y = probabilite, fill = modele)) +
  geom_col(width = 0.5) +
  geom_text(aes(label = scales::scientific(probabilite, digits = 2)),
            vjust = -0.5, size = 3.5) +
  scale_y_log10(labels = scales::scientific) +
  scale_fill_manual(values = c("Normal" = "grey50", "Student-t" = "firebrick")) +
  labs(title = "Probabilité d'un mouvement de -2.67% (échelle log)",
       subtitle = str_wrap("Normal : ~1 fois tous les 2.3M ans  |  Student-t : ~1 fois tous les 14 ans", width = 65),
       x = NULL, y = "Probabilité (échelle log10)") +
  theme(legend.position = "none")

save_fig(g9, "09_tail_probability_comparison.png")

# ==============================================================================
cat("Terminé —", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")