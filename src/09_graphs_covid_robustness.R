# ==============================================================================
# Graphs — Covid_Robustness_Test.md
# Génère les 5 figures identifiées pour ce document.
# Sortie : PNG, 300 dpi, dans graphs/Covid_robustness_plot/
#
# Architecture (identique aux scripts précédents) :
#   src/                          <- ce script
#   data/processed/               <- covid_full_comparison_table.csv
#   graphs/Covid_robustness_plot/ <- PNG produits ici
#
# Seul covid_full_comparison_table.csv est utilisé (il contient déjà les
# bandes de confiance, l'OHLC, prob_stress et les flags de dépassement —
# les 3 autres CSV fournis sont redondants pour ces 5 graphs précis).
#
# Toutes les statistiques (couverture 91.7%, test binomial, dates et
# directions des 7 dépassements, dépassements intrajournaliers) ont été
# revérifiées indépendamment depuis le CSV et correspondent exactement au
# document.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Covid_robustness_plot")
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
covid_df <- read_csv(file.path(processed_dir, "covid_full_comparison_table.csv"),
                     col_types = cols(target_date = col_date(), p_min = col_double(),
                                      p_max = col_double(), actual_price = col_double(),
                                      Open = col_double(), High = col_double(), Low = col_double(),
                                      Close = col_double(), inside_range = col_logical(),
                                      prob_stress = col_double(),
                                      close_breach_direction = col_character(),
                                      low_below_pmin = col_logical(), high_above_pmax = col_logical()))

# ==============================================================================
# GRAPH 1 — Plage prévue (ruban) vs OHLC réel, sur les 84 jours
# ==============================================================================
touch_df <- covid_df %>%
  mutate(touch = case_when(
    !inside_range ~ "Dépassement Close",
    low_below_pmin | high_above_pmax ~ "Dépassement intrajournalier seul",
    TRUE ~ "Dans la plage"
  ))

g1 <- ggplot(covid_df, aes(x = target_date)) +
  geom_ribbon(aes(ymin = p_min, ymax = p_max), fill = "steelblue3", alpha = 0.3) +
  geom_linerange(aes(ymin = Low, ymax = High), color = "grey40", linewidth = 0.3) +
  geom_point(data = touch_df, aes(y = Close, color = touch), size = 1.6) +
  scale_color_manual(values = c("Dans la plage" = "grey30",
                                "Dépassement intrajournalier seul" = "goldenrod3",
                                "Dépassement Close" = "firebrick")) +
  labs(title = "Test out-of-sample COVID — plage à 95% vs. OHLC réel (janv-avril 2020)",
       subtitle = str_wrap("Modèle figé, pré-2020 — 7 dépassements en clôture, 19 jours touchant hors bande en intrajournalier", width = 70),
       x = NULL, y = "EUR/USD", color = NULL)

save_fig(g1, "01_covid_ribbon_ohlc_84days.png", width = 10, height = 5)

# ==============================================================================
# GRAPH 2 — Les 7 dépassements en clôture : Groupe A vs Groupe B (P(stress))
# ==============================================================================
breach_df <- covid_df %>%
  filter(!inside_range) %>%
  mutate(groupe = ifelse(prob_stress < 0.5, "Groupe A (régime pas encore réagi)",
                         "Groupe B (stress déjà signalé >95%)"),
         prob_stress_pct = prob_stress * 100)

g2 <- ggplot(breach_df, aes(x = target_date, y = prob_stress_pct, color = groupe)) +
  geom_hline(yintercept = c(50, 95), linetype = "dotted", color = "grey50") +
  geom_segment(aes(xend = target_date, y = 0, yend = prob_stress_pct), linewidth = 0.5) +
  geom_point(size = 4) +
  geom_text(aes(label = format(target_date, "%d %b")), vjust = -1, size = 3, show.legend = FALSE) +
  scale_color_manual(values = c("Groupe A (régime pas encore réagi)" = "darkorange3",
                                "Groupe B (stress déjà signalé >95%)" = "firebrick")) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Les 7 dépassements en clôture — deux groupes distincts",
       subtitle = str_wrap("Groupe A : le régime n'avait pas encore réagi. Groupe B : stress déjà signalé, bande quand même trop étroite", width = 65),
       x = NULL, y = "P(régime de stress) au moment de la prévision, %", color = NULL)

save_fig(g2, "02_breach_groups_A_B.png")

# ==============================================================================
# GRAPH 3 — Taux de dépassement selon la définition (Close / High / Low / Combiné)
# ==============================================================================
n_total <- nrow(covid_df)
breach_types <- tibble(
  type = c("Close seul", "High > borne haute", "Low < borne basse", "Combiné (unique)"),
  n = c(sum(!covid_df$inside_range), sum(covid_df$high_above_pmax),
        sum(covid_df$low_below_pmin),
        sum(!covid_df$inside_range | covid_df$high_above_pmax | covid_df$low_below_pmin)),
) %>%
  mutate(pct = n / n_total * 100,
         type = factor(type, levels = type))

g3 <- ggplot(breach_types, aes(x = type, y = pct, fill = type)) +
  geom_col(width = 0.6) +
  geom_hline(yintercept = 5, linetype = "dashed", color = "grey40") +
  geom_text(aes(label = paste0(n, "/", n_total, " (", round(pct, 1), "%)")), vjust = -0.5, size = 3.5) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  scale_fill_manual(values = c("Close seul" = "steelblue3", "High > borne haute" = "darkorange3",
                               "Low < borne basse" = "goldenrod3", "Combiné (unique)" = "firebrick")) +
  labs(title = "Taux de dépassement selon la définition retenue",
       subtitle = str_wrap("Ligne pointillée = 5% nominal — le taux \u00abunique\u00bb (22.6%) est ~2.7x le taux Close (8.3%)", width = 65),
       x = NULL, y = "% des 84 jours") +
  theme(legend.position = "none", axis.text.x = element_text(angle = 15, hjust = 1))

save_fig(g3, "03_breach_rate_by_definition.png")

# ==============================================================================
# GRAPH 4 — Test binomial : distribution sous H0 (p=5%) vs observé (k=7)
# ==============================================================================
k_range <- 0:20
binom_df <- tibble(
  k = k_range,
  proba = dbinom(k_range, size = n_total, prob = 0.05),
  zone = ifelse(k_range >= 7, "k \u2265 7 (zone du test unilatéral)", "k < 7")
)

g4 <- ggplot(binom_df, aes(x = k, y = proba, fill = zone)) +
  geom_col(width = 0.7) +
  geom_vline(xintercept = 7, linetype = "dashed", color = "firebrick", linewidth = 0.8) +
  annotate("text", x = 7.5, y = max(binom_df$proba) * 0.9,
           label = "Observé : k = 7\np unilatéral = 0.127", hjust = 0, color = "firebrick", size = 3.5) +
  scale_fill_manual(values = c("k < 7" = "grey70", "k \u2265 7 (zone du test unilatéral)" = "firebrick")) +
  labs(title = "Distribution binomiale sous H0 (n=84, p=5%) — k = 7 observé",
       subtitle = str_wrap("La zone rouge cumulée donne p = 0.127 — pas de preuve significative de sous-couverture", width = 65),
       x = "Nombre de dépassements (k)", y = "P(K = k) sous H0", fill = NULL)

save_fig(g4, "04_binomial_test_visualization.png")

# ==============================================================================
# GRAPH 5 — Taux de "surprise" pour un utilisateur : Close vs intrajournalier
# ==============================================================================
surprise_df <- tibble(
  base = factor(c("Décision basée sur\nla clôture (Close)", "Décision basée sur\nl'intrajournalier (tout contact)"),
                levels = c("Décision basée sur\nla clôture (Close)", "Décision basée sur\nl'intrajournalier (tout contact)")),
  frequence = c(1/12, 1/4) * 100
)

g5 <- ggplot(surprise_df, aes(x = base, y = frequence, fill = base)) +
  geom_col(width = 0.5) +
  geom_text(aes(label = c("~1 jour sur 12", "~1 jour sur 4")), vjust = -0.5, size = 4) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  scale_fill_manual(values = c("Décision basée sur\nla clôture (Close)" = "steelblue3",
                               "Décision basée sur\nl'intrajournalier (tout contact)" = "firebrick")) +
  labs(title = "Fréquence de \u00absurprise\u00bb pour un utilisateur du modèle",
       subtitle = str_wrap("Le même modèle, deux lectures très différentes du risque selon l'usage qu'on en fait", width = 65),
       x = NULL, y = "% des jours où le prix sort de la plage à 95%") +
  theme(legend.position = "none")

save_fig(g5, "05_user_surprise_rate.png")

# ==============================================================================
cat("Terminé —", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")