# ==============================================================================
# Graphs — Regime_hmm.md
# Génère les 7 figures identifiées pour ce document.
# Sortie : PNG, 300 dpi, dans graphs/Regime_hmm_plot/
#
# Architecture (identique aux scripts précédents) :
#   src/                     <- ce script
#   data/processed/          <- regime_hmm_output.csv
#   graphs/Regime_hmm_plot/  <- PNG produits ici
#
# Vérification indépendante effectuée (Python, à partir du CSV réel) :
# fréquences des régimes, moyennes/écarts-types par régime, matrice de
# transition et classification des 10 derniers jours — tout correspond
# exactement à Regime_hmm.md section 4. Aucune incohérence trouvée.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Regime_hmm_plot")
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

# Palette cohérente sur tous les graphs de ce document
regime_colors <- c(
  "low volatility"                  = "steelblue3",
  "normal volatility"               = "goldenrod3",
  "high volatility (stress/panic)"  = "firebrick"
)
regime_levels <- c("low volatility", "normal volatility", "high volatility (stress/panic)")

# ---- 1. Chargement des données -------------------------------------------
hmm_df <- read_csv(file.path(processed_dir, "regime_hmm_output.csv"),
                   col_types = cols(Date = col_date(), sigma_t = col_double(),
                                    log_sigma_t = col_double(), state = col_integer(),
                                    regime_label = col_character())) %>%
  mutate(regime_label = factor(regime_label, levels = regime_levels))

# ==============================================================================
# GRAPH 1 — sigma(t) sur toute la période, coloré par régime
# ==============================================================================
g1 <- ggplot(hmm_df, aes(x = Date, y = sigma_t, color = regime_label)) +
  geom_point(size = 0.4, alpha = 0.6) +
  scale_color_manual(values = regime_colors) +
  labs(title = "Volatilité conditionnelle \u03c3(t) — classification par régime (HMM)",
       x = NULL, y = "\u03c3(t)", color = "Régime")

save_fig(g1, "01_sigma_by_regime_fullsample.png", width = 9, height = 4.5)

# ==============================================================================
# GRAPH 2 — Diagnostic de convergence : log-vraisemblance sur 10 restarts
#           (section 4.1)
# ==============================================================================
convergence_df <- tibble(
  restart = 0:9,
  loglik = c(-745.41, 1665.67, 3302.55, 3302.55, 3302.55,
             3302.55, 3302.55, 3302.55, 3302.55, 3302.55)
)

g2 <- ggplot(convergence_df, aes(x = factor(restart), y = loglik)) +
  geom_col(fill = "steelblue4", width = 0.6) +
  geom_hline(yintercept = 3302.55, linetype = "dashed", color = "firebrick") +
  annotate("text", x = 8.5, y = 2900, label = "Optimum global\n(8/10 restarts)",
           color = "firebrick", size = 3.3) +
  labs(title = "Convergence du HMM sur 10 initialisations aléatoires",
       subtitle = str_wrap("8/10 restarts convergent vers l'optimum global (log-vraisemblance = 3302.55)", width = 65),
       x = "Restart (random_state)", y = "Log-vraisemblance")

save_fig(g2, "02_hmm_convergence_restarts.png")

# ==============================================================================
# GRAPH 3 — Distribution de log(sigma(t)) par régime — séparation des états
# ==============================================================================
g3 <- ggplot(hmm_df, aes(x = log_sigma_t, fill = regime_label)) +
  geom_density(alpha = 0.55, color = NA) +
  scale_fill_manual(values = regime_colors) +
  labs(title = "Distribution de log(\u03c3(t)) par régime",
       subtitle = str_wrap("Trois états bien séparés — contraste avec la première tentative dégénérée (section 3)", width = 65),
       x = "log(\u03c3(t))", y = "Densité", fill = "Régime")

save_fig(g3, "03_density_logsigma_by_regime.png")

# ==============================================================================
# GRAPH 4 — Fréquence de chaque régime (% du temps)
# ==============================================================================
freq_df <- hmm_df %>%
  count(regime_label) %>%
  mutate(pct = n / sum(n) * 100)

g4 <- ggplot(freq_df, aes(x = regime_label, y = pct, fill = regime_label)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = paste0(round(pct, 1), "%")), vjust = -0.5, size = 3.8) +
  scale_fill_manual(values = regime_colors) +
  labs(title = "Fréquence de chaque régime (2010-2026)",
       subtitle = str_wrap("Le marché passe environ 1 jour sur 3 en régime de stress", width = 65),
       x = NULL, y = "% des jours de trading") +
  theme(legend.position = "none")

save_fig(g4, "04_regime_frequency.png")

# ==============================================================================
# GRAPH 5 — Matrice de transition (heatmap)
# ==============================================================================
trans_df <- tribble(
  ~from,                             ~to,                                ~prob,
  "low volatility",                  "low volatility",                  0.9921,
  "low volatility",                  "normal volatility",               0.0079,
  "low volatility",                  "high volatility (stress/panic)",  0.0000,
  "normal volatility",               "low volatility",                  0.0067,
  "normal volatility",               "normal volatility",               0.9861,
  "normal volatility",               "high volatility (stress/panic)",  0.0072,
  "high volatility (stress/panic)",  "low volatility",                  0.0000,
  "high volatility (stress/panic)",  "normal volatility",               0.0090,
  "high volatility (stress/panic)",  "high volatility (stress/panic)",  0.9910
) %>%
  mutate(from = factor(from, levels = regime_levels),
         to   = factor(to, levels = rev(regime_levels)))

g5 <- ggplot(trans_df, aes(x = from, y = to, fill = prob)) +
  geom_tile(color = "white", linewidth = 0.8) +
  geom_text(aes(label = scales::percent(prob, accuracy = 0.1)), size = 4) +
  scale_fill_gradient(low = "white", high = "steelblue4", labels = scales::percent) +
  labs(title = "Matrice de transition entre régimes",
       subtitle = str_wrap("Diagonale dominante — forte persistance intra-régime", width = 65),
       x = "Régime au jour t", y = "Régime au jour t+1", fill = "Probabilité")

save_fig(g5, "05_transition_matrix_heatmap.png")

# ==============================================================================
# GRAPH 6 — Durée moyenne implicite de chaque régime (jours)
# ==============================================================================
duration_df <- tibble(
  regime_label = factor(regime_levels, levels = regime_levels),
  duree_jours = c(127, 72, 111)
)

g6 <- ggplot(duration_df, aes(x = regime_label, y = duree_jours, fill = regime_label)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = paste0("~", duree_jours, " j")), vjust = -0.5, size = 3.8) +
  scale_fill_manual(values = regime_colors) +
  labs(title = "Durée moyenne implicite d'un régime",
       subtitle = str_wrap("1 / (1 - p_reste) — un régime dure plusieurs mois, pas quelques jours", width = 65),
       x = NULL, y = "Durée moyenne (jours de trading)") +
  theme(legend.position = "none")

save_fig(g6, "06_regime_implied_duration.png")

# ==============================================================================
# GRAPH 7 — Zoom sur la période récente (12 derniers mois ~ 250 jours)
#           Contexte pour la classification actuelle (section 4.4, 6.3)
# ==============================================================================
recent_df <- hmm_df %>% slice_tail(n = 250)

g7 <- ggplot(recent_df, aes(x = Date, y = sigma_t, color = regime_label)) +
  geom_line(aes(group = 1), color = "grey70", linewidth = 0.3) +
  geom_point(size = 1.3) +
  scale_color_manual(values = regime_colors) +
  labs(title = "\u03c3(t) — 12 derniers mois de l'échantillon",
       subtitle = str_wrap("Les 10 derniers jours sont classés en régime de faible volatilité", width = 65),
       x = NULL, y = "\u03c3(t)", color = "Régime")

save_fig(g7, "07_recent_period_zoom.png", width = 8, height = 4.5)

# ==============================================================================
cat("Terminé —", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")