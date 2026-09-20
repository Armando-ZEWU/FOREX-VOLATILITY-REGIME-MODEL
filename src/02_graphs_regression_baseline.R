# ==============================================================================
# Graphs — Regression_baseline.md
# Génère les 5 figures identifiées pour ce document.
# Sortie : PNG, 300 dpi, dans graphs/Regresion_baseline/
#
# Architecture (identique à 01_graphs_garch_1_1.R) :
#   src/                      <- ce script
#   data/processed/           <- regression_dataset_baseline.csv
#   graphs/Regresion_baseline/ <- PNG produits ici
#
# NOTE DE RIGUEUR (à lire) : Regression_baseline.md §6.1 qualifie delta_y_t
# = ±0.05 à ±0.20 de "typique, sans caractère remarquable". Vérification
# faite sur le CSV réel : 0.05 correspond au 95e percentile empirique, et
# 0.20 est proche du 99.5e-99.9e percentile (94.6% des observations sont
# déjà sous ±0.05 en valeur absolue). Le graph 4 ci-dessous affiche donc les
# percentiles réels plutôt que de reprendre telle quelle la formulation
# "typique" du document — corrige le texte de ton .md en conséquence.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Regresion_baseline_plot")
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
reg_df <- read_csv(file.path(processed_dir, "regression_dataset_baseline.csv"),
                   col_types = cols(Date = col_date(), r_t = col_double(),
                                    delta_y_t = col_double(), r_t_plus_1 = col_double()))

# Coefficients publiés — Regression_baseline.md section 5 (OLS + erreurs HAC/Newey-West)
coef_const     <- -0.0051
coef_delta_y   <- -0.1546;  se_delta_y <- 0.240
coef_r_t       <-  0.0206;  se_r_t     <- 0.017

# ==============================================================================
# GRAPH 1 — r(t+1) vs delta_y(t), avec droite OLS
# ==============================================================================
g1 <- ggplot(reg_df, aes(x = delta_y_t, y = r_t_plus_1)) +
  geom_point(alpha = 0.25, size = 0.8, color = "steelblue4") +
  geom_smooth(method = "lm", color = "firebrick", se = TRUE, linewidth = 0.9) +
  labs(title = "r(t+1) vs. \u0394y(t) — choc de volatilité GARCH",
       subtitle = "R\u00b2 \u2248 0.0005 — aucune relation visible, cohérent avec le résultat nul",
       x = "\u0394y(t) = ln(\u03c3(t)/\u03c3(t-1))", y = "r(t+1) — rendement log (%)")

save_fig(g1, "01_scatter_rt1_vs_deltay.png")

# ==============================================================================
# GRAPH 2 — r(t+1) vs r(t), avec droite OLS
# ==============================================================================
g2 <- ggplot(reg_df, aes(x = r_t, y = r_t_plus_1)) +
  geom_point(alpha = 0.25, size = 0.8, color = "darkorange3") +
  geom_smooth(method = "lm", color = "firebrick", se = TRUE, linewidth = 0.9) +
  labs(title = "r(t+1) vs. r(t) — momentum / mean-reversion à 1 jour",
       subtitle = "\u03b2\u2082 \u2248 0.0206, p = 0.218 — aucun effet détecté",
       x = "r(t) — rendement log (%)", y = "r(t+1) — rendement log (%)")

save_fig(g2, "02_scatter_rt1_vs_rt.png")

# ==============================================================================
# GRAPH 3 — Forest plot des coefficients (IC 95%, erreurs HAC)
# ==============================================================================
coef_df <- tibble(
  variable = c("\u03b2\u2081 : \u0394y(t)\n(choc de volatilité)",
               "\u03b2\u2082 : r(t)\n(rendement retardé)"),
  coef = c(coef_delta_y, coef_r_t),
  se   = c(se_delta_y, se_r_t)
) %>%
  mutate(ci_low = coef - 1.96 * se, ci_high = coef + 1.96 * se)

g3 <- ggplot(coef_df, aes(x = coef, y = variable)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.15, orientation = "y",
                color = "steelblue4", linewidth = 0.8) +
  geom_point(size = 3, color = "firebrick") +
  labs(title = "Coefficients de la régression baseline — IC 95% (erreurs HAC)",
       subtitle = "Les deux intervalles traversent zéro — aucun effet statistiquement détecté",
       x = "Estimation du coefficient", y = NULL)

save_fig(g3, "03_forest_plot_coefficients.png")

# ==============================================================================
# GRAPH 4 — Effet prédit de delta_y(t), avec repères de percentiles réels
#           (corrige la formulation "typique" du §6.1 — voir note en tête de script)
# ==============================================================================
pct_marks <- quantile(reg_df$delta_y_t, probs = c(0.50, 0.95, 0.99), na.rm = TRUE)

x_range <- seq(min(reg_df$delta_y_t), max(reg_df$delta_y_t), length.out = 200)
pred_df <- tibble(
  delta_y_t = x_range,
  r_pred = coef_const + coef_delta_y * x_range
)

pct_df <- tibble(
  percentile = c("P50 (médiane)", "P95", "P99"),
  x = as.numeric(pct_marks)
)

g4 <- ggplot(pred_df, aes(x = delta_y_t, y = r_pred)) +
  geom_line(color = "firebrick", linewidth = 1) +
  geom_vline(data = pct_df, aes(xintercept = x), linetype = "dotted", color = "grey40") +
  geom_text(data = pct_df, aes(x = x, y = max(pred_df$r_pred), label = percentile),
            angle = 90, vjust = -0.5, hjust = 1, size = 3, color = "grey30") +
  labs(title = "Effet prédit de \u0394y(t) sur r(t+1) — à coefficient pris au sérieux",
       subtitle = "P95 et P99 marquent les niveaux réellement observés, pas des valeurs \u00abtypiques\u00bb (voir note de script)",
       x = "\u0394y(t)", y = "r(t+1) prédit (%)")

save_fig(g4, "04_predicted_effect_with_percentiles.png")

# ==============================================================================
# GRAPH 5 — Distribution empirique de delta_y(t) avec percentiles annotés
# ==============================================================================
g5 <- ggplot(reg_df, aes(x = delta_y_t)) +
  geom_histogram(bins = 100, fill = "steelblue3", alpha = 0.7, color = "white", linewidth = 0.1) +
  geom_vline(data = pct_df, aes(xintercept = x), linetype = "dashed", color = "firebrick") +
  geom_text(data = pct_df, aes(x = x, y = Inf, label = percentile),
            angle = 90, vjust = 1.3, hjust = 1.1, size = 3, color = "firebrick") +
  labs(title = "Distribution empirique de \u0394y(t)",
       subtitle = "94.6% des observations sont déjà sous ±0.05 en valeur absolue",
       x = "\u0394y(t)", y = "Fréquence")

save_fig(g5, "05_distribution_deltay_percentiles.png")

# ==============================================================================
cat("Terminé —", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")