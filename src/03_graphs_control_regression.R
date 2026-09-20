# ==============================================================================
# Graphs — Control_Regression.md
# Génère les 6 figures identifiées pour ce document.
# Sortie : PNG, 300 dpi, dans graphs/Control_regression/
#
# Architecture (identique aux scripts précédents) :
#   src/                        <- ce script
#   data/processed/             <- regression_dataset_extended.csv
#   graphs/Control_regression/  <- PNG produits ici
#
# Tous les coefficients/erreurs-types ci-dessous ont été revérifiés
# indépendamment (statsmodels, OLS + HAC/Newey-West maxlags=5) et
# correspondent exactement à Control_Regression.md section 5.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Control_regression_plot")
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
ext_df <- read_csv(file.path(processed_dir, "regression_dataset_extended.csv"),
                    col_types = cols(Date = col_date(), r_t = col_double(),
                                      delta_y_t = col_double(), r_t_plus_1 = col_double(),
                                      diff_rate = col_double(), r_dxy = col_double()))

# ==============================================================================
# GRAPH 1 — Stabilité de beta_1 (delta_y_t) avant/après contrôles
#           Le test central de ce document (section 5.3)
# ==============================================================================
beta1_df <- tibble(
  etape = factor(c("Avant contrôles", "Après contrôles"),
                  levels = c("Avant contrôles", "Après contrôles")),
  coef = c(-0.1329, -0.1308),
  se   = c(0.238793, 0.239006),
  p    = c(0.578, 0.584)
) %>% mutate(ci_low = coef - 1.96 * se, ci_high = coef + 1.96 * se)

g1 <- ggplot(beta1_df, aes(x = etape, y = coef)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  geom_line(aes(group = 1), color = "grey60", linewidth = 0.6) +
  geom_errorbar(aes(ymin = ci_low, ymax = ci_high), width = 0.08, color = "steelblue4", linewidth = 0.8) +
  geom_point(size = 3.5, color = "firebrick") +
  geom_text(aes(label = paste0("\u03b2\u2081 = ", coef, "\n(p = ", p, ")")),
            vjust = -1.2, size = 3.3) +
  labs(title = "Stabilité de \u03b2\u2081 (\u0394y(t)) avant/après ajout des contrôles",
       subtitle = "Variation \u2248 1.6% en magnitude — aucune preuve de confusion",
       x = NULL, y = "Coefficient \u03b2\u2081")

save_fig(g1, "01_beta1_stability.png")

# ==============================================================================
# GRAPH 2 — Comparaison AIC/BIC : baseline réestimée vs modèle étendu
# ==============================================================================
fit_comparison <- tibble(
  modele = rep(c("Baseline (réestimée)", "Étendu (+ contrôles)"), times = 2),
  metrique = rep(c("AIC", "BIC"), each = 2),
  valeur = c(6334.45, 6337.11,   # AIC
             6353.44, 6368.77)   # BIC
) %>% mutate(modele = factor(modele, levels = c("Baseline (réestimée)", "Étendu (+ contrôles)")))

g2 <- ggplot(fit_comparison, aes(x = metrique, y = valeur, fill = modele)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6) +
  coord_cartesian(ylim = c(6300, 6400)) +
  scale_fill_manual(values = c("Baseline (réestimée)" = "grey50", "Étendu (+ contrôles)" = "firebrick")) +
  labs(title = "AIC / BIC — l'ajout des contrôles dégrade l'ajustement",
       subtitle = "Les deux critères favorisent le modèle baseline, sans les contrôles",
       x = NULL, y = "Valeur (zoom sur la plage pertinente)", fill = "Modèle")

save_fig(g2, "02_aic_bic_comparison.png")

# ==============================================================================
# GRAPH 3 — Forest plot : coefficients à échelle compacte
#           (delta_y_t, r_t, diff_rate — hors r_dxy, voir graph 4)
# ==============================================================================
coef_compact <- tibble(
  variable = c("\u0394y(t)\n(choc de volatilité)", "r(t)\n(rendement retardé)", "diff_rate\n(différentiel Fed-BCE)"),
  coef = c(-0.130819, 0.023532, 0.009977),
  se   = c(0.239006, 0.029971, 0.008804)
) %>%
  mutate(ci_low = coef - 1.96 * se, ci_high = coef + 1.96 * se,
         variable = fct_rev(factor(variable, levels = variable)))

g3 <- ggplot(coef_compact, aes(x = coef, y = variable)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.15, orientation = "y",
                color = "steelblue4", linewidth = 0.8) +
  geom_point(size = 3, color = "firebrick") +
  labs(title = "Modèle étendu — coefficients à échelle compacte",
       subtitle = "r_dxy exclu ici (IC bien plus large — voir graph séparé)",
       x = "Estimation du coefficient", y = NULL)

save_fig(g3, "03_forest_plot_compact.png")

# ==============================================================================
# GRAPH 4 — r_dxy seul : l'IC 95% est si large qu'il est peu informatif
#           (-9.0 à +10.7 — section 6.1 du document)
# ==============================================================================
r_dxy_df <- tibble(
  variable = "r_dxy\n(rendement DXY proxy)",
  coef = 0.859127,
  ci_low = -9.018844,
  ci_high = 10.737099
)

g4 <- ggplot(r_dxy_df, aes(x = coef, y = variable)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.1, orientation = "y",
                color = "steelblue4", linewidth = 1) +
  geom_point(size = 3.5, color = "firebrick") +
  annotate("text", x = 0, y = 1.3,
           label = "IC 95% : [-9.0 ; +10.7] — compatible avec\nune relation forte dans un sens, dans l'autre,\nou aucune relation du tout",
           size = 3.3, color = "grey30") +
  coord_cartesian(ylim = c(0.7, 1.5)) +
  labs(title = "r_dxy — un coefficient statistiquement non-informatif",
       subtitle = "Pas juste \u00abnon significatif\u00bb : l'estimation ne permet même pas de fixer le signe",
       x = "Estimation du coefficient", y = NULL)

save_fig(g4, "04_r_dxy_wide_ci.png")

# ==============================================================================
# GRAPH 5 — r(t+1) vs diff_rate, avec droite OLS
# ==============================================================================
g5 <- ggplot(ext_df, aes(x = diff_rate, y = r_t_plus_1)) +
  geom_point(alpha = 0.25, size = 0.8, color = "steelblue4") +
  geom_smooth(method = "lm", color = "firebrick", se = TRUE, linewidth = 0.9) +
  labs(title = "r(t+1) vs. différentiel de taux (Fed - BCE)",
       subtitle = "\u03b2\u2083 \u2248 0.0100, p = 0.257 — aucune relation détectée",
       x = "diff_rate(t) — points de pourcentage", y = "r(t+1) — rendement log (%)")

save_fig(g5, "05_scatter_rt1_vs_diffrate.png")

# ==============================================================================
# GRAPH 6 — r(t+1) vs r_dxy, avec droite OLS
# ==============================================================================
g6 <- ggplot(ext_df, aes(x = r_dxy, y = r_t_plus_1)) +
  geom_point(alpha = 0.25, size = 0.8, color = "darkorange3") +
  geom_smooth(method = "lm", color = "firebrick", se = TRUE, linewidth = 0.9) +
  labs(title = "r(t+1) vs. rendement du proxy DXY",
       subtitle = "\u03b2\u2084 \u2248 0.859, p = 0.865 — estimation non-informative (voir graph 4)",
       x = "r_dxy(t)", y = "r(t+1) — rendement log (%)")

save_fig(g6, "06_scatter_rt1_vs_rdxy.png")

# ==============================================================================
cat("Terminé —", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")
