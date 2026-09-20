# ==============================================================================
# Graphs — Garch_Stability.md
# Génère les 5 figures identifiées pour ce document.
# Sortie : PNG, 300 dpi, dans graphs/Garch_stability_plot/
#
# Architecture (identique aux scripts précédents) :
#   src/                          <- ce script
#   data/processed/               <- garch_stability_comparison.csv
#   graphs/Garch_stability_plot/  <- PNG produits ici
#
# Vérification indépendante effectuée (Python) : somme des log-vraisemblances
# des 5 sous-périodes (-2806.77), test LR (23.25 ≈ 23.24 publié, p=0.277),
# et somme AIC (5663.53) — tout correspond exactement à Garch_Stability.md.
#
# NOTE : le graph 4 (omega par période) ne marque QUE la Période 2 comme
# "non significatif" — c'est la seule période pour laquelle le document
# fournit un p-value (0.519, issu d'un refit ad hoc, section 4). Les
# p-values des périodes 1/3/4/5 ne sont pas dans le CSV ni dans le texte
# (cf. section 6.2 du document, "reproducibility gap" déjà notée) — donc
# je ne les invente pas, et le graph reste honnête sur ce qu'on sait
# vraiment.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)
library(patchwork)

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Garch_stability_plot")
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
stab_df <- read_csv(file.path(processed_dir, "garch_stability_comparison.csv"),
                    col_types = cols(period = col_character(), start_date = col_date(),
                                     end_date = col_date(), n_obs = col_integer(),
                                     omega = col_double(), alpha = col_double(), beta = col_double(),
                                     nu = col_double(), alpha_plus_beta = col_double(),
                                     half_life_days = col_double(), log_likelihood = col_double(),
                                     aic = col_double())) %>%
  mutate(period = factor(period, levels = paste("Period", 1:5)),
         half_life_reliable = period != "Period 2")

# ==============================================================================
# GRAPH 1 — alpha+beta vs demi-vie implicite, côte à côte
#           Illustre la non-linéarité : petits écarts de alpha+beta -> grands
#           écarts de demi-vie, près de la frontière IGARCH (alpha+beta = 1)
# ==============================================================================
p_ab <- ggplot(stab_df, aes(x = period, y = alpha_plus_beta)) +
  geom_col(fill = "steelblue3", width = 0.6) +
  geom_text(aes(label = sprintf("%.4f", alpha_plus_beta)), vjust = -0.5, size = 3.2) +
  coord_cartesian(ylim = c(0.98, 1.001)) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
  labs(title = "\u03b1 + \u03b2 (persistance)", x = NULL, y = "\u03b1 + \u03b2")

p_hl <- ggplot(stab_df %>% filter(half_life_reliable), aes(x = period, y = half_life_days)) +
  geom_col(fill = "firebrick", width = 0.6) +
  geom_text(aes(label = paste0(round(half_life_days, 0), " j")), vjust = -0.5, size = 3.2) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Demi-vie implicite (Période 2 exclue)", x = NULL, y = "Jours de trading")

g1 <- (p_ab | p_hl) +
  plot_annotation(
    title = "Un petit écart de persistance, un grand écart de demi-vie",
    subtitle = str_wrap("La non-linéarité de ln(0.5)/ln(\u03b1+\u03b2) près de la frontière IGARCH amplifie des différences de \u03b1+\u03b2 de 0.007-0.008 en des écarts de demi-vie de plusieurs mois", width = 100)
  )

save_fig(g1, "01_alphabeta_vs_halflife.png", width = 9, height = 4.5)

# ==============================================================================
# GRAPH 2 — Demi-vie par période, échelle log, Période 2 annotée comme
#           non significative (pas exclue, mais clairement signalée)
# ==============================================================================
g2 <- ggplot(stab_df, aes(x = period, y = half_life_days, fill = half_life_reliable)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = ifelse(half_life_reliable,
                               paste0(round(half_life_days, 0), " j"),
                               "Non significatif\n(voir note)")),
            vjust = -0.3, size = 3.2) +
  scale_y_log10(labels = scales::comma, expand = expansion(mult = c(0.05, 0.25))) +
  scale_fill_manual(values = c("TRUE" = "steelblue3", "FALSE" = "grey60")) +
  labs(title = "Demi-vie implicite par période (échelle log)",
       subtitle = str_wrap("Période 2 : \u03c9 non significatif (p=0.519) près de la frontière IGARCH -> ratio numériquement instable, chiffre à ne jamais citer seul", width = 65),
       x = NULL, y = "Demi-vie (jours, échelle log)") +
  theme(legend.position = "none")

save_fig(g2, "02_halflife_log_scale.png")

# ==============================================================================
# GRAPH 3 — Modèle unique vs 5 modèles séparés : LL / AIC / BIC
#           (test du rapport de vraisemblance, section 5.1)
# ==============================================================================
fit_comparison <- tibble(
  modele = rep(c("Modèle unique\n(5 paramètres)", "5 modèles séparés\n(25 paramètres)"), times = 3),
  metrique = rep(c("-2 x Log-vraisemblance", "AIC", "BIC"), each = 2),
  valeur = c(2 * 2818.39, 2 * 2806.77,   # -2LL
             5646.78, 5663.53,            # AIC
             5678.46, 5821.95)            # BIC
) %>% mutate(metrique = factor(metrique, levels = c("-2 x Log-vraisemblance", "AIC", "BIC")))

g3 <- ggplot(fit_comparison, aes(x = modele, y = valeur, fill = modele)) +
  geom_col(width = 0.6) +
  facet_wrap(~metrique, scales = "free_y") +
  scale_fill_manual(values = c("Modèle unique\n(5 paramètres)" = "steelblue3",
                               "5 modèles séparés\n(25 paramètres)" = "firebrick")) +
  labs(title = "Test du rapport de vraisemblance : LR=23.25, df=20, p=0.277",
       subtitle = str_wrap("AIC et BIC préfèrent tous deux le modèle unique — la flexibilité supplémentaire ne se justifie pas", width = 65),
       x = NULL, y = "Valeur") +
  theme(legend.position = "none", axis.text.x = element_text(angle = 15, hjust = 1))

save_fig(g3, "03_single_vs_5period_model.png", width = 8, height = 4.5)

# ==============================================================================
# GRAPH 4 — omega par période — seule la Période 2 est signalée non
#           significative (les autres n'ont pas de p-value publiée, voir note)
# ==============================================================================
g4 <- ggplot(stab_df, aes(x = period, y = omega, fill = half_life_reliable)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = ifelse(half_life_reliable, sprintf("%.4f", omega), "p=0.519\n(non sign.)")),
            vjust = -0.4, size = 3.1) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.2))) +
  scale_fill_manual(values = c("TRUE" = "steelblue3", "FALSE" = "grey60")) +
  labs(title = "\u03c9 (variance de long terme, non normalisée) par période",
       subtitle = str_wrap("Seule la significativité de la Période 2 est documentée (p=0.519, refit ad hoc) — celle des 4 autres périodes n'est pas publiée (voir section 6.2 du document)", width = 65),
       x = NULL, y = "\u03c9") +
  theme(legend.position = "none")

save_fig(g4, "04_omega_by_period.png")

# ==============================================================================
# GRAPH 5 — Le récit "période calme" contredit : % de jours en régime de
#           stress, 2014 vs 2015 (dans la Période 2) vs moyenne d'ensemble
# ==============================================================================
narrative_df <- tibble(
  annee = factor(c("2014\n(dans Période 2)", "2015\n(dans Période 2)", "Moyenne 2010-2026\n(toutes périodes)"),
                 levels = c("2014\n(dans Période 2)", "2015\n(dans Période 2)", "Moyenne 2010-2026\n(toutes périodes)")),
  pct_stress = c(26.4, 68.1, 28.3)
)

g5 <- ggplot(narrative_df, aes(x = annee, y = pct_stress, fill = annee)) +
  geom_col(width = 0.55) +
  geom_hline(yintercept = 28.3, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0(pct_stress, "%")), vjust = -0.5, size = 4) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  scale_fill_manual(values = c("2014\n(dans Période 2)" = "goldenrod3",
                               "2015\n(dans Période 2)" = "firebrick",
                               "Moyenne 2010-2026\n(toutes périodes)" = "steelblue3")) +
  labs(title = "Le récit \u00abpériode calme\u00bb ne tient pas — 2015 était l'une des années les plus stressées",
       subtitle = str_wrap("% de jours en régime de stress (classification MS-GARCH, ms_garch.md) — 2015 dépasse largement la moyenne d'ensemble", width = 65),
       x = NULL, y = "% des jours en régime de stress") +
  theme(legend.position = "none")

save_fig(g5, "05_calm_narrative_debunked.png")

# ==============================================================================
cat("Terminé —", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")