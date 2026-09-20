# ==============================================================================
# Graphs — Rolling_Test.md
# Génère les 5 figures identifiées pour ce document.
# Sortie : PNG, 300 dpi, dans graphs/Rolling_test_plot/
#
# Architecture (identique aux scripts précédents) :
#   src/                     <- ce script
#   data/processed/          <- rolling_test_chain_result.csv,
#                                rolling_fan_chart_inputs.csv
#   graphs/Rolling_test_plot/ <- PNG produits ici
#
# NOTE : les valeurs Open/High/Low de la section 3.1 du document ne sont
# dans AUCUN CSV fourni — elles sont reprises telles quelles depuis le texte
# de Rolling_Test.md (tibble ohlc_df ci-dessous), pas lues depuis un fichier.
#
# NOTE 2 : le document décrit 4 fan charts SÉPARÉS (une image par jour de
# prévision, section 4). Le graph 1 ci-dessous les consolide en UNE seule
# figure à 4 panneaux (facet) — plus pratique pour un document de recherche
# qu'un jeu de 4 fichiers distincts. Dis-moi si tu préfères 4 fichiers séparés
# à la place, c'est un choix de présentation, pas une contrainte technique.
#
# Toutes les valeurs ont été revérifiées indépendamment (recalcul Python
# depuis les CSV et le texte) et correspondent exactement au document.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Rolling_test_plot")
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
chain_df <- read_csv(file.path(processed_dir, "rolling_test_chain_result.csv"),
                     col_types = cols(cutoff_date = col_date(), cutoff_price = col_double(),
                                      target_date = col_date(), p_min = col_double(),
                                      p_max = col_double(), range_width_pct = col_double(),
                                      actual_price = col_double(), inside_range = col_logical(),
                                      prob_calm = col_double(), prob_stress = col_double()))

fan_df <- read_csv(file.path(processed_dir, "rolling_fan_chart_inputs.csv"),
                   col_types = cols(cutoff_date = col_date(), target_date = col_date(),
                                    confidence_level = col_double(), p_min = col_double(),
                                    p_max = col_double(), actual_price = col_double()))

# OHLC — repris du texte de Rolling_Test.md section 3.1 (pas de CSV source)
ohlc_df <- tribble(
  ~target_date,              ~open,   ~high,   ~low,    ~close,
  as.Date("2026-09-14"),     1.1597,  1.1601,  1.1523,  1.1549,
  as.Date("2026-09-15"),     1.1549,  1.1553,  1.1527,  1.1542,
  as.Date("2026-09-16"),     1.1542,  1.1557,  1.1461,  1.1464,
  as.Date("2026-09-17"),     1.1464,  1.1473,  1.1457,  1.1459
)

# ==============================================================================
# GRAPH 1 — Fan chart consolidé, 4 panneaux (un par jour de prévision)
# ==============================================================================
fan_df2 <- fan_df %>%
  mutate(confidence_level = factor(confidence_level,
                                   levels = sort(unique(confidence_level), decreasing = TRUE)),
         panel = paste0("Cible : ", format(target_date, "%d %b")))

actual_pts <- chain_df %>%
  mutate(panel = paste0("Cible : ", format(target_date, "%d %b")),
         breach = ifelse(inside_range, "Dans la plage (95%)", "Hors plage (95%)"))

g1 <- ggplot(fan_df2, aes(x = 1)) +
  geom_rect(aes(xmin = 0.6, xmax = 1.4, ymin = p_min, ymax = p_max, fill = confidence_level),
            alpha = 0.6) +
  geom_point(data = actual_pts, aes(x = 1, y = actual_price, color = breach), size = 3.5, inherit.aes = FALSE) +
  facet_wrap(~panel, nrow = 1) +
  scale_fill_brewer(palette = "Blues", direction = -1, labels = scales::percent) +
  scale_color_manual(values = c("Dans la plage (95%)" = "grey20", "Hors plage (95%)" = "firebrick")) +
  scale_x_continuous(breaks = NULL) +
  labs(title = "Test séquentiel à 1 jour — bandes de confiance et prix réel",
       subtitle = str_wrap("Semaine FOMC, 11-17 septembre 2026 — le 16 septembre est le seul jour hors de la bande à 95%", width = 70),
       x = NULL, y = "EUR/USD", fill = "Niveau de\nconfiance", color = NULL)

save_fig(g1, "01_rolling_fanchart_4panels.png", width = 10, height = 4.5)

# ==============================================================================
# GRAPH 2 — Plage prévue (ruban 95%) vs prix réel, sur toute la chaîne
# ==============================================================================
range95 <- chain_df %>% mutate(breach = ifelse(inside_range, "Dans la plage", "Hors plage"))

g2 <- ggplot(range95, aes(x = target_date)) +
  geom_ribbon(aes(ymin = p_min, ymax = p_max), fill = "steelblue3", alpha = 0.35) +
  geom_line(aes(y = p_min), color = "steelblue4", linewidth = 0.4, linetype = "dashed") +
  geom_line(aes(y = p_max), color = "steelblue4", linewidth = 0.4, linetype = "dashed") +
  geom_line(aes(y = actual_price), color = "grey30", linewidth = 0.6) +
  geom_point(aes(y = actual_price, color = breach), size = 3.5) +
  scale_color_manual(values = c("Dans la plage" = "grey20", "Hors plage" = "firebrick")) +
  labs(title = "Chaîne de prévisions à 1 jour — plage 95% vs. réalisé",
       subtitle = str_wrap("3 jours sur 4 dans la plage (Close) — le seul écart, le 16 septembre, de 7 pips", width = 65),
       x = NULL, y = "EUR/USD", color = NULL)

save_fig(g2, "02_range_vs_actual_chain.png")

# ==============================================================================
# GRAPH 3 — OHLC vs plage à 95%, sur les 4 jours (extension de price_range.md §7)
# ==============================================================================
ohlc_long <- ohlc_df %>%
  pivot_longer(c(open, high, low, close), names_to = "type", values_to = "valeur") %>%
  mutate(type = recode(type, open = "Open", high = "High", low = "Low", close = "Close"),
         type = factor(type, levels = c("Open", "High", "Low", "Close")))

range95_chain <- chain_df %>% select(target_date, p_min, p_max)

g3 <- ggplot() +
  geom_rect(data = range95_chain, aes(xmin = target_date - 0.3, xmax = target_date + 0.3,
                                      ymin = p_min, ymax = p_max),
            fill = "steelblue3", alpha = 0.3) +
  geom_point(data = ohlc_long, aes(x = target_date, y = valeur, shape = type, color = type), size = 3) +
  scale_color_brewer(palette = "Dark2") +
  labs(title = "OHLC quotidien vs. plage prévue à 95%",
       subtitle = str_wrap("Le Low sort de la bande 2 fois (14 et 16 sept.) ; le Close, référence du modèle, 1 seule fois (16 sept.)", width = 65),
       x = NULL, y = "EUR/USD", color = NULL, shape = NULL)

save_fig(g3, "03_ohlc_vs_range_chain.png", width = 8, height = 4.5)

# ==============================================================================
# GRAPH 4 — P(stress) vs largeur de la plage, sur la chaîne (section 5.3)
# ==============================================================================
dual_df <- chain_df %>%
  transmute(target_date, prob_stress = prob_stress * 100, range_width_pct = range_width_pct * 100) %>%
  pivot_longer(-target_date, names_to = "serie", values_to = "valeur") %>%
  mutate(serie = recode(serie, prob_stress = "P(régime de stress), %",
                        range_width_pct = "Largeur de la plage, % du prix"))

g4 <- ggplot(dual_df, aes(x = target_date, y = valeur, color = serie)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2.5) +
  facet_wrap(~serie, scales = "free_y") +
  scale_color_manual(values = c("P(régime de stress), %" = "firebrick",
                                "Largeur de la plage, % du prix" = "steelblue4")) +
  labs(title = "La probabilité de stress grimpe x5 — la largeur de plage bouge à peine",
       subtitle = str_wrap("Comportement attendu à paramètres figés, ou lenteur structurelle à réagir ? Indécidable sur n=4 (§5.3)", width = 65),
       x = NULL, y = NULL) +
  theme(legend.position = "none")

save_fig(g4, "04_prob_stress_vs_range_width.png", width = 8.5, height = 4.5)

# ==============================================================================
# GRAPH 5 — Impact économique du quasi-échec (prévision 3, cible 16 sept.)
# ==============================================================================
econ_df <- tibble(
  label = factor(c("Borne basse\nprévue (95%)", "Réalisé\n(Close 16 sept.)", "Borne haute\nprévue (95%)"),
                 levels = c("Borne basse\nprévue (95%)", "Réalisé\n(Close 16 sept.)", "Borne haute\nprévue (95%)")),
  valeur_usd = c(1147100, 1146400, 1161300),
  type = c("Prévu", "Réalisé", "Prévu")
)

g5 <- ggplot(econ_df, aes(x = label, y = valeur_usd, fill = type)) +
  geom_col(width = 0.5) +
  geom_text(aes(label = paste0("$", scales::comma(valeur_usd))), vjust = -0.5, size = 3.8) +
  scale_y_continuous(labels = scales::dollar, expand = expansion(mult = c(0, 0.15))) +
  scale_fill_manual(values = c("Prévu" = "steelblue3", "Réalisé" = "firebrick")) +
  labs(title = "Conversion de EUR 1 000 000 — le \u00abéchec\u00bb du 16 septembre en dollars",
       subtitle = str_wrap("Écart réel : environ $700 sous la borne basse — un quasi-échec, pas un échec matériel", width = 65),
       x = NULL, y = "Produit de la conversion (USD)") +
  theme(legend.position = "none")

save_fig(g5, "05_economic_near_miss.png")

# ==============================================================================
cat("Terminé —", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")