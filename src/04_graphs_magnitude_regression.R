# ==============================================================================
# Graphs — Magnitude_Regression.md
# Génère les 6 figures identifiées pour ce document.
# Sortie : PNG, 300 dpi, dans graphs/Magnitude_regression_plot/
#
# Architecture (identique aux scripts précédents) :
#   src/                              <- ce script
#   data/processed/                   <- magnitude_regression_dataset.csv
#   graphs/Magnitude_regression_plot/ <- PNG produits ici
#
# NOTE DE RIGUEUR (à lire) : Magnitude_Regression.md section 5 illustre le
# modèle avec sigma_t = 0.25 ("jour calme") et sigma_t = 0.60 ("jour
# turbulent"). Vérification sur le CSV réel : 0.25 correspond au 0.1e
# percentile (quasi le plancher historique), 0.60 au 71.6e percentile
# (à peine au-dessus de la médiane) — pas deux points symétriquement
# représentatifs. Le graph 5 ci-dessous utilise donc P10/P50/P90 comme
# repères, pas les valeurs 0.25/0.60 du document. Corrige le texte du .md
# si tu gardes cette illustration dans le papier final.
#
# Tous les coefficients ont été revérifiés indépendamment (statsmodels,
# OLS + HAC/Newey-West maxlags=5) et correspondent exactement à
# Magnitude_Regression.md section 4.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Magnitude_regression_plot")
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
mag_df <- read_csv(file.path(processed_dir, "magnitude_regression_dataset.csv"),
                    col_types = cols(Date = col_date(), r_t = col_double(),
                                      abs_r_t = col_double(), sigma_t = col_double(),
                                      delta_y_t = col_double(), abs_r_t_plus_1 = col_double()))

# ==============================================================================
# GRAPH 1 — Spec A : |r(t+1)| vs delta_y(t), avec droite OLS
# ==============================================================================
g1 <- ggplot(mag_df, aes(x = delta_y_t, y = abs_r_t_plus_1)) +
  geom_point(alpha = 0.25, size = 0.8, color = "steelblue4") +
  geom_smooth(method = "lm", color = "firebrick", se = TRUE, linewidth = 0.9) +
  labs(title = "Spec A — |r(t+1)| vs. \u0394y(t)",
       subtitle = "b\u2081 \u2248 -0.087, p = 0.583 — le choc (variation) n'explique pas la magnitude",
       x = "\u0394y(t) = ln(\u03c3(t)/\u03c3(t-1))", y = "|r(t+1)| (%)")

save_fig(g1, "01_specA_scatter_deltay.png")

# ==============================================================================
# GRAPH 2 — Spec B : |r(t+1)| vs sigma(t) (niveau), avec droite OLS
# ==============================================================================
g2 <- ggplot(mag_df, aes(x = sigma_t, y = abs_r_t_plus_1)) +
  geom_point(alpha = 0.25, size = 0.8, color = "darkorange3") +
  geom_smooth(method = "lm", color = "firebrick", se = TRUE, linewidth = 0.9) +
  labs(title = "Spec B — |r(t+1)| vs. \u03c3(t) (niveau)",
       subtitle = "b\u2081 \u2248 0.703, p < 0.001, R\u00b2 = 0.090 — le niveau explique la magnitude",
       x = "\u03c3(t) — volatilité conditionnelle", y = "|r(t+1)| (%)")

save_fig(g2, "02_specB_scatter_sigma.png")

# ==============================================================================
# GRAPH 3 — Comparaison des specs : R² / AIC / BIC
# ==============================================================================
spec_comparison <- tibble(
  spec = rep(c("Spec A (\u0394y(t))", "Spec B (\u03c3(t) niveau)"), times = 3),
  metrique = rep(c("R\u00b2 (\u00d7100 pour lisibilité)", "AIC", "BIC"), each = 2),
  valeur = c(1.32, 9.03,          # R² x100
             3026.94, 2687.29,    # AIC
             3045.95, 2706.30)    # BIC
) %>% mutate(metrique = factor(metrique, levels = c("R\u00b2 (\u00d7100 pour lisibilité)", "AIC", "BIC")))

g3 <- ggplot(spec_comparison, aes(x = spec, y = valeur, fill = spec)) +
  geom_col(width = 0.6) +
  facet_wrap(~metrique, scales = "free_y") +
  scale_fill_manual(values = c("Spec A (\u0394y(t))" = "grey50", "Spec B (\u03c3(t) niveau)" = "firebrick")) +
  labs(title = "Spec A vs Spec B — le niveau domine sur tous les critères",
       x = NULL, y = "Valeur") +
  theme(legend.position = "none", axis.text.x = element_text(angle = 20, hjust = 1))

save_fig(g3, "03_specA_vs_specB_fit.png", width = 8, height = 4)

# ==============================================================================
# GRAPH 4 — La significativité bascule : variable de choc vs |r(t)|, par spec
# ==============================================================================
sig_df <- tibble(
  spec = rep(c("Spec A (\u0394y(t))", "Spec B (\u03c3(t) niveau)"), each = 2),
  variable = rep(c("Variable de choc", "|r(t)|"), times = 2),
  coef = c(-0.0871, 0.1148,   # Spec A: delta_y_t, abs_r_t
            0.7029, 0.0269),  # Spec B: sigma_t, abs_r_t
  p = c(0.583, 5.29e-11,
        1.56e-67, 0.101)
) %>%
  mutate(significatif = ifelse(p < 0.05, "Significatif (p<0.05)", "Non significatif"),
         neg_log10_p = -log10(p))

g4 <- ggplot(sig_df, aes(x = variable, y = neg_log10_p, fill = significatif)) +
  geom_col(width = 0.55) +
  geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "grey30") +
  facet_wrap(~spec) +
  scale_fill_manual(values = c("Significatif (p<0.05)" = "firebrick", "Non significatif" = "grey60")) +
  labs(title = "La significativité bascule entre |r(t)| et la variable de choc",
       subtitle = "Ligne pointillée = seuil p = 0.05 (-log10(0.05) \u2248 1.30)",
       x = NULL, y = "-log10(p-value)", fill = NULL)

save_fig(g4, "04_significance_flip.png", width = 8, height = 4.5)

# ==============================================================================
# GRAPH 5 — Exemple économique : |r(t+1)| prédit vs sigma(t), avec P10/P50/P90
#           (remplace les exemples 0.25/0.60 du document — voir note en tête)
# ==============================================================================
const_b <- 0.017123; coef_b <- 0.702860
sigma_range <- seq(min(mag_df$sigma_t), max(mag_df$sigma_t), length.out = 200)
pred_df <- tibble(sigma_t = sigma_range, pred = const_b + coef_b * sigma_range)

pct_sigma <- quantile(mag_df$sigma_t, probs = c(0.10, 0.50, 0.90))
pct_df <- tibble(
  percentile = c("P10", "P50", "P90"),
  x = as.numeric(pct_sigma),
  pred = const_b + coef_b * as.numeric(pct_sigma)
)

g5 <- ggplot(pred_df, aes(x = sigma_t, y = pred)) +
  geom_line(color = "firebrick", linewidth = 1) +
  geom_point(data = pct_df, aes(x = x, y = pred), size = 3, color = "steelblue4") +
  geom_text(data = pct_df, aes(x = x, y = pred, label = paste0(percentile, "\n", round(pred, 2), "%")),
            vjust = -0.6, size = 3.2, color = "steelblue4") +
  labs(title = "|r(t+1)| prédit selon \u03c3(t) — repères P10/P50/P90",
       subtitle = "Repères choisis pour être représentatifs (voir note de script sur les exemples du document)",
       x = "\u03c3(t)", y = "|r(t+1)| prédit (%)")

save_fig(g5, "05_predicted_magnitude_percentiles.png")

# ==============================================================================
# GRAPH 6 — Distribution empirique de sigma(t), avec P10/P50/P90 annotés
# ==============================================================================
g6 <- ggplot(mag_df, aes(x = sigma_t)) +
  geom_histogram(bins = 80, fill = "steelblue3", alpha = 0.7, color = "white", linewidth = 0.1) +
  geom_vline(data = pct_df, aes(xintercept = x), linetype = "dashed", color = "firebrick") +
  geom_text(data = pct_df, aes(x = x, y = Inf, label = percentile),
            angle = 90, vjust = 1.3, hjust = 1.1, size = 3, color = "firebrick") +
  labs(title = "Distribution empirique de \u03c3(t)",
       subtitle = "Pour contexte : 0.25 (exemple \u00abcalme\u00bb du document) est proche du minimum historique",
       x = "\u03c3(t)", y = "Fréquence")

save_fig(g6, "06_distribution_sigma_percentiles.png")

# ==============================================================================
cat("Terminé —", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")
