# ==============================================================================
# Graphs — Full_Backtest.md
# Génère les 5 figures identifiées pour ce document.
# Sortie : PNG, 300 dpi, dans graphs/Full_backtest_plot/
#
# Architecture (identique aux scripts précédents) :
#   src/                       <- ce script
#   data/processed/            <- full_backtest_result.csv,
#                                  full_backtest_fold_diagnostics.csv
#   graphs/Full_backtest_plot/ <- PNG produits ici
#
# POINT DE VIGILANCE (à lire) : Full_Backtest.md section 4 affirme que
# l'alerte SE(nu2) > nu2 se déclenche dans "11 des 14 folds". Recalcul
# depuis le CSV : 10 folds sur 14 (folds 1, 3, 6, 14 ne sont PAS flagués).
# Le graph 4 ci-dessous calcule ce compte DYNAMIQUEMENT depuis le CSV, donc
# il affichera automatiquement le bon chiffre — vérifie et corrige le texte
# du .md en conséquence.
#
# Tout le reste (couverture globale 95.50%, p=0.919, couverture par année,
# fold 8 vs ms_garch_pre2020.R, fold 3/2015 IGARCH, fold 6/2018) a été
# revérifié indépendamment et correspond exactement au document.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)
library(ggrepel)

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Full_backtest_plot")
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
result_df <- read_csv(file.path(processed_dir, "full_backtest_result.csv"),
                      col_types = cols(fold = col_integer(), test_year = col_integer(),
                                       target_date = col_date(), p_min = col_double(),
                                       p_max = col_double(), actual_price = col_double(),
                                       inside_range = col_logical(), prob_calm = col_double(),
                                       prob_stress = col_double()))

diag_df <- read_csv(file.path(processed_dir, "full_backtest_fold_diagnostics.csv"),
                    col_types = cols(fold = col_integer(), test_year = col_integer(),
                                     converged = col_logical(), alpha_beta_1 = col_double(),
                                     alpha_beta_2 = col_double(), nu_1 = col_double(),
                                     nu_2 = col_double(), nu_1_se = col_double(),
                                     nu_2_se = col_double(), P_1_1 = col_double(),
                                     P_2_1 = col_double(), P_1_2 = col_double(),
                                     P_2_2 = col_double()))

n_total <- nrow(result_df)

# ==============================================================================
# GRAPH 1 — Couverture par année, avec événements de marché annotés
# ==============================================================================
by_year <- result_df %>%
  group_by(test_year) %>%
  summarise(n = n(), breaches = sum(!inside_range), .groups = "drop") %>%
  mutate(coverage_pct = (1 - breaches / n) * 100)

events_df <- tribble(
  ~test_year, ~label,
  2013, "Taper tantrum",
  2015, "SNB / Grèce / QE",
  2016, "Brexit / élection US",
  2020, "COVID-19",
  2022, "Ukraine / parité"
) %>% left_join(by_year, by = "test_year")

g1 <- ggplot(by_year, aes(x = factor(test_year), y = coverage_pct)) +
  geom_col(fill = "steelblue3", width = 0.65) +
  geom_hline(yintercept = 95, linetype = "dashed", color = "firebrick", linewidth = 0.7) +
  geom_text(data = events_df, aes(label = label), vjust = -0.5, size = 2.9, color = "grey20",
            angle = 90, hjust = 0) +
  coord_cartesian(ylim = c(85, 100)) +
  labs(title = "Couverture empirique par année (2013-2026)",
       subtitle = str_wrap("Ligne pointillée = cible nominale 95% — 2015 est la seule année nettement sous la cible", width = 70),
       x = NULL, y = "Couverture empirique (%)") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

save_fig(g1, "01_coverage_by_year_events.png", width = 10, height = 5)

# ==============================================================================
# GRAPH 2 — Test binomial global : distribution sous H0 vs observé (k=154, n=3424)
# ==============================================================================
k_range <- 100:250
binom_df <- tibble(
  k = k_range,
  proba = dbinom(k_range, size = n_total, prob = 0.05),
  zone = ifelse(k_range >= sum(!result_df$inside_range), "k \u2265 observé", "k < observé")
)
k_obs <- sum(!result_df$inside_range)

g2 <- ggplot(binom_df, aes(x = k, y = proba)) +
  geom_col(fill = "steelblue3", width = 1) +
  geom_vline(xintercept = k_obs, linetype = "dashed", color = "firebrick", linewidth = 0.9) +
  annotate("text", x = k_obs + 5, y = max(binom_df$proba) * 0.85,
           label = paste0("Observé : k = ", k_obs, "\np unilatéral = 0.919"),
           hjust = 0, color = "firebrick", size = 3.6) +
  labs(title = "Test binomial (n=3 424, p=5% sous H0) — premier test réellement puissant du projet",
       subtitle = str_wrap("k=154 dépassements observés — même en dessous du nombre attendu (171) sous H0", width = 65),
       x = "Nombre de dépassements (k)", y = "P(K = k) sous H0")

save_fig(g2, "02_binomial_test_full.png")

# ==============================================================================
# GRAPH 3 — alpha+beta par régime, à travers les 14 folds — repère IGARCH
# ==============================================================================
ab_long <- diag_df %>%
  select(test_year, alpha_beta_1, alpha_beta_2) %>%
  pivot_longer(-test_year, names_to = "regime", values_to = "alpha_beta") %>%
  mutate(regime = recode(regime, alpha_beta_1 = "Régime 1 (calme)", alpha_beta_2 = "Régime 2 (stress)"))

g3 <- ggplot(ab_long, aes(x = factor(test_year), y = alpha_beta, color = regime, group = regime)) +
  geom_hline(yintercept = 1, linetype = "dotted", color = "grey30") +
  geom_line(linewidth = 0.6) +
  geom_point(size = 2.5) +
  annotate("text", x = "2015", y = 0.97, label = "Frontière IGARCH\n(2015, fold 3)",
           color = "firebrick", size = 3, vjust = 1) +
  scale_color_manual(values = c("Régime 1 (calme)" = "steelblue4", "Régime 2 (stress)" = "firebrick")) +
  labs(title = "Persistance (\u03b1+\u03b2) par régime, à travers les 14 folds",
       subtitle = str_wrap("2015 est le seul fold à ~0.0001 de la frontière IGARCH (\u03b1+\u03b2=1)", width = 65),
       x = NULL, y = "\u03b1 + \u03b2", color = NULL) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

save_fig(g3, "03_alphabeta_by_fold.png", width = 9, height = 4.5)

# ==============================================================================
# GRAPH 4 — nu2 : estimation +/- erreur-type, à travers les 14 folds
#           (compte de folds flagués calculé DYNAMIQUEMENT — voir note en tête)
# ==============================================================================
nu2_df <- diag_df %>%
  mutate(flag = nu_2_se > nu_2,
         ci_low = pmax(nu_2 - nu_2_se, 0), ci_high = nu_2 + nu_2_se)

n_flagged <- sum(nu2_df$flag)

g4 <- ggplot(nu2_df, aes(x = factor(test_year), y = nu_2, color = flag)) +
  geom_errorbar(aes(ymin = ci_low, ymax = ci_high), width = 0.25, linewidth = 0.7) +
  geom_point(size = 3) +
  scale_color_manual(values = c("TRUE" = "firebrick", "FALSE" = "steelblue4"),
                     labels = c("TRUE" = "SE > \u03bd2 (mal identifié)", "FALSE" = "SE < \u03bd2")) +
  labs(title = paste0("\u03bd2 (queue du régime de stress) \u00b1 erreur-type, par fold"),
       subtitle = str_wrap(paste0(n_flagged, " des 14 folds ont SE(\u03bd2) > \u03bd2 — difficulté récurrente à identifier ce paramètre, pas un accident isolé"), width = 65),
       x = NULL, y = "\u03bd2", color = NULL) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

save_fig(g4, "04_nu2_precision_by_fold.png", width = 9, height = 4.5)

# ==============================================================================
# GRAPH 5 — Le régime 2 du fold 6 (2018) est un cas à part
# ==============================================================================
regime2_df <- diag_df %>%
  mutate(is_fold6 = fold == 6,
         label = ifelse(is_fold6, paste0(test_year, " (atypique)"), as.character(test_year)))

g5 <- ggplot(regime2_df, aes(x = alpha_beta_2, y = nu_2, color = is_fold6)) +
  geom_point(size = 3.5) +
  geom_text_repel(aes(label = label), size = 3, show.legend = FALSE,
                  max.overlaps = Inf, box.padding = 0.4, seed = 42) +
  scale_color_manual(values = c("TRUE" = "firebrick", "FALSE" = "steelblue4")) +
  scale_y_continuous(expand = expansion(mult = c(0.05, 0.12))) +
  labs(title = "Le régime de stress du fold 6 (2018) ne ressemble à aucun autre",
       subtitle = str_wrap("Faible persistance interne (\u03b1+\u03b22 bas) + \u03bd2 élevé et bien identifié -> un état rare, calme et stable, pas un régime de panique", width = 65),
       x = "\u03b1 + \u03b2 (régime 2)", y = "\u03bd2", color = NULL) +
  theme(legend.position = "none")

save_fig(g5, "05_fold6_regime2_outlier.png")

# ==============================================================================
cat("Terminé —", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")