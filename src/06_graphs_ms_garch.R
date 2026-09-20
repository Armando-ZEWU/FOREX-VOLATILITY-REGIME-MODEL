# ==============================================================================
# Graphs — Markov-Switching_Garch.md
# Génère les 6 figures identifiées pour ce document.
# Sortie : PNG, 300 dpi, dans graphs/Markov-Switching_GARCH_plot/
#
# Architecture (identique aux scripts précédents) :
#   src/                                    <- ce script
#   data/processed/                         <- ms_garch_regime_probs.csv,
#                                               ms_garch_transition_matrix.csv
#   graphs/Markov-Switching_GARCH_plot/     <- PNG produits ici
#
# POINT DE VIGILANCE (à lire) : Markov-Switching_Garch.md section 6 affirme
# "2010-2012 ... 39-100% high-vol days". Vérification sur le CSV réel :
# 2010≈100%, 2011≈81%, 2012≈0% (la probabilité lissée du régime de stress ne
# dépasse jamais 44% en 2012). Le graph 5 ci-dessous calcule ce comptage
# DYNAMIQUEMENT depuis le CSV plutôt que de reprendre le chiffre "39-100%"
# du texte — vérifie ce que ça donne et recoupe avec ton script ms_garch.R
# avant de citer ce chiffre dans le papier.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

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

# ---- 1. Chargement des données -------------------------------------------
probs_df <- read_csv(file.path(processed_dir, "ms_garch_regime_probs.csv"),
                     col_types = cols(Date = col_date(), log_return = col_double(),
                                      prob_regime_1 = col_double(), prob_regime_2 = col_double()))

trans_raw <- read_csv(file.path(processed_dir, "ms_garch_transition_matrix.csv"),
                      col_types = cols())

# ==============================================================================
# GRAPH 1 — Probabilité lissée du régime de stress (régime 2), pleine période
# ==============================================================================
g1 <- ggplot(probs_df, aes(x = Date, y = prob_regime_2)) +
  geom_area(fill = "firebrick", alpha = 0.4) +
  geom_line(color = "firebrick", linewidth = 0.3) +
  geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey40") +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Probabilité lissée du régime de stress — P(régime 2)",
       subtitle = str_wrap("Ligne pointillée = seuil 50% (classification type-Viterbi)", width = 65),
       x = NULL, y = "P(régime de stress)")

save_fig(g1, "01_smoothed_prob_regime2_fullsample.png", width = 9, height = 4.5)

# ==============================================================================
# GRAPH 2 — Étude de cas COVID : zoom janvier-juin 2020
# ==============================================================================
covid_df <- probs_df %>% filter(Date >= as.Date("2020-01-01"), Date <= as.Date("2020-06-30"))

milestone_dates <- as.Date(c("2020-02-18","2020-02-25","2020-02-26","2020-02-28",
                             "2020-03-11","2020-03-19","2020-04-01","2020-04-17","2020-04-30"))
milestones_df <- covid_df %>% filter(Date %in% milestone_dates)

g2 <- ggplot(covid_df, aes(x = Date, y = prob_regime_2)) +
  geom_line(color = "firebrick", linewidth = 0.7) +
  geom_point(data = milestones_df, size = 2.2, color = "steelblue4") +
  geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey40") +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Détection du choc COVID-19 — probabilité de régime de stress",
       subtitle = str_wrap("9% \u2192 99.998% en ~3 semaines (18 fév. \u2192 11 mars 2020)", width = 65),
       x = NULL, y = "P(régime de stress)")

save_fig(g2, "02_covid_case_study.png")

# ==============================================================================
# GRAPH 3 — Demi-vie intra-régime vs durée de régime (Markov)
#           Section 4.3 : "le stress s'estompe plus vite qu'il ne dure"
# ==============================================================================
comparison_df <- tibble(
  regime = rep(c("Régime 1 (calme)", "Régime 2 (stress)"), times = 2),
  concept = rep(c("Demi-vie intra-régime\n(vitesse de décroissance du choc GARCH)",
                  "Durée de régime\n(temps avant un changement de régime)"), each = 2),
  jours = c(237.1, 63.9,    # demi-vies
            404, 160)       # durées Markov
) %>% mutate(regime = factor(regime, levels = c("Régime 1 (calme)", "Régime 2 (stress)")))

g3 <- ggplot(comparison_df, aes(x = regime, y = jours, fill = regime)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = paste0(jours, " j")), vjust = -0.5, size = 3.6) +
  facet_wrap(~concept) +
  scale_fill_manual(values = c("Régime 1 (calme)" = "steelblue3", "Régime 2 (stress)" = "firebrick")) +
  labs(title = "Deux échelles de temps distinctes, à ne pas confondre",
       subtitle = str_wrap("Le stress s'estompe plus vite (demi-vie) qu'il ne dure comme régime", width = 65),
       x = NULL, y = "Jours de trading") +
  theme(legend.position = "none")

save_fig(g3, "03_halflife_vs_regime_duration.png", width = 8, height = 4.5)

# ==============================================================================
# GRAPH 4 — Comparaison LL / AIC / BIC : GARCH simple vs MS-GARCH
# ==============================================================================
fit_comparison <- tibble(
  modele = rep(c("GARCH simple", "MS-GARCH (K=2)"), times = 3),
  metrique = rep(c("Log-vraisemblance", "AIC", "BIC"), each = 2),
  valeur = c(-2818.39, -2806.64,   # LL
             5646.78, 5633.27,     # AIC
             5678.46, 5696.64)     # BIC
) %>% mutate(metrique = factor(metrique, levels = c("Log-vraisemblance", "AIC", "BIC")))

g4 <- ggplot(fit_comparison, aes(x = modele, y = valeur, fill = modele)) +
  geom_col(width = 0.6) +
  facet_wrap(~metrique, scales = "free_y") +
  scale_fill_manual(values = c("GARCH simple" = "grey50", "MS-GARCH (K=2)" = "firebrick")) +
  labs(title = "GARCH simple vs MS-GARCH — AIC et BIC en désaccord",
       subtitle = str_wrap("AIC favorise MS-GARCH ; BIC favorise le modèle simple — désaccord non tranché, documenté tel quel", width = 65),
       x = NULL, y = "Valeur") +
  theme(legend.position = "none", axis.text.x = element_text(angle = 20, hjust = 1))

save_fig(g4, "04_model_comparison_ll_aic_bic.png", width = 8, height = 4)

# ==============================================================================
# GRAPH 5 — % de jours en régime de stress par année (calculé dynamiquement)
#           Voir la note en tête de script sur l'écart trouvé pour 2012
# ==============================================================================
yearly_df <- probs_df %>%
  mutate(year = year(Date), high_vol_day = prob_regime_2 > 0.5) %>%
  group_by(year) %>%
  summarise(pct_high_vol = mean(high_vol_day) * 100, .groups = "drop")

g5 <- ggplot(yearly_df, aes(x = factor(year), y = pct_high_vol)) +
  geom_col(fill = "firebrick", alpha = 0.8) +
  geom_hline(yintercept = 50, linetype = "dotted", color = "grey50") +
  labs(title = "% de jours en régime de stress, par année (calcul dynamique depuis le CSV)",
       subtitle = str_wrap("Vérifie en particulier 2012 — voir note en tête de script", width = 65),
       x = NULL, y = "% des jours de trading en régime de stress") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

save_fig(g5, "05_yearly_stress_regime_pct.png", width = 9, height = 4.5)

# ==============================================================================
# GRAPH 6 — Matrice de transition (heatmap, K=2)
# ==============================================================================
trans_long <- trans_raw %>%
  rename(from = 1) %>%
  pivot_longer(-from, names_to = "to", values_to = "prob") %>%
  mutate(
    from = recode(from, "t|k=1" = "Régime 1 (calme)", "t|k=2" = "Régime 2 (stress)"),
    to   = recode(to,  "t+1|k=1" = "Régime 1 (calme)", "t+1|k=2" = "Régime 2 (stress)"),
    to   = fct_rev(factor(to, levels = c("Régime 1 (calme)", "Régime 2 (stress)")))
  )

g6 <- ggplot(trans_long, aes(x = from, y = to, fill = prob)) +
  geom_tile(color = "white", linewidth = 1) +
  geom_text(aes(label = scales::percent(prob, accuracy = 0.01)), size = 4.5) +
  scale_fill_gradient(low = "white", high = "firebrick", labels = scales::percent) +
  labs(title = "Matrice de transition — MS-GARCH (K=2)",
       subtitle = str_wrap("Forte persistance des deux régimes", width = 65),
       x = "Régime au jour t", y = "Régime au jour t+1", fill = "Probabilité")

save_fig(g6, "06_transition_matrix_k2.png")

# ==============================================================================
cat("Terminé —", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")