# ==============================================================================
# Graphs — Rolling_Test.md
# Génère les 2 figures retenues pour le document Rolling_Test.md
# Sortie : PNG, 300 dpi, dans graphs/Rolling_Test_plot/
#
# Entrées :
#   data/processed/rolling_test_chain_result.csv   4 prévisions (95 %, verdict, probabilités)
#   data/processed/rolling_fan_chart_inputs.csv    bandes 20/50/80/95 % par prévision
#   data/raw/eurusd_daily.csv                      historique FRED (Date, Close)
#   OHLC des 4 jours cibles : recopié à la main du tableau §3.1 de Rolling_Test.md
#   (source Pound Sterling Live). Aucun CSV ne le contient -> voir bloc OHLC
#   ci-dessous. Le contrôle de la section 3 vérifie la recopie contre le CSV.
#
# Mapping figure -> section du document :
#   01  §3, §3.1, §4   4 panneaux (un par prévision) : bandes + chandelier réel
#   02  §5.3           P(stress) vs largeur de la fourchette, indexés base 100
#
# Non générés (volontairement) : l'illustration en dollars du §6 (chiffres dans
# le texte) et les tableaux du §3 (portent déjà l'information).
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ---- 0. Chemins ---------------------------------------------------------
raw_dir       <- here("data", "raw")
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Rolling_Test_plot")
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

col_band <- "steelblue3"  # bandes en bleu clair : le corps du chandelier (noir/blanc) reste lisible
col_out  <- "firebrick"   # hors de la bande 95 %

# ---- 1. Chargement -------------------------------------------------------
chain <- read_csv(file.path(processed_dir, "rolling_test_chain_result.csv"),
                  col_types = cols(cutoff_date = col_date(), cutoff_price = col_double(),
                                   target_date = col_date(), p_min = col_double(),
                                   p_max = col_double(), range_width_pct = col_double(),
                                   actual_price = col_double(), inside_range = col_logical(),
                                   prob_calm = col_double(), prob_stress = col_double()))

fan <- read_csv(file.path(processed_dir, "rolling_fan_chart_inputs.csv"),
                col_types = cols(cutoff_date = col_date(), target_date = col_date(),
                                 confidence_level = col_double(), p_min = col_double(),
                                 p_max = col_double(), actual_price = col_double()))

daily <- read_csv(file.path(raw_dir, "eurusd_daily.csv"),
                  col_types = cols(Date = col_date(), Close = col_double()))

# ---- 2. OHLC recopié de Rolling_Test.md §3.1 (Pound Sterling Live) ---------
ohlc <- tibble(
  target_date = as.Date(c("2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17")),
  open  = c(1.1597, 1.1549, 1.1542, 1.1464),
  high  = c(1.1601, 1.1553, 1.1557, 1.1473),
  low   = c(1.1523, 1.1527, 1.1461, 1.1457),
  close = c(1.1549, 1.1542, 1.1464, 1.1459)
)

chain <- chain %>%
  arrange(target_date) %>%
  mutate(forecast = row_number()) %>%
  left_join(ohlc, by = "target_date")

out_of <- function(x, lo, hi) x < lo | x > hi

# ---- 3. CONTRÔLE (s'imprime dans la console R) ---------------------------
check <- function(label, got, doc, tol) {
  ok <- all(abs(got - doc) <= tol)
  cat(sprintf("%-46s obtenu: %-34s doc: %-34s [%s]\n", label,
              paste(round(got, 4), collapse = " / "),
              paste(doc, collapse = " / "),
              if (ok) "OK" else "ÉCART"))
  ok
}

cat("\n================ CONTRÔLE ROLLING_TEST ================\n")
res <- c(
  check("Clôtures OHLC recopiées = actual_price (CSV)", chain$close, chain$actual_price, 1e-9),
  check("Largeurs 95 % (%), doc §3", 100 * chain$range_width_pct, c(1.22, 1.23, 1.23, 1.29), 5e-3),
  check("P(stress) (%), doc §3", 100 * chain$prob_stress, c(0.6, 1.1, 0.8, 3.0), 5e-2),
  check("P(calm) (%), doc §3", 100 * chain$prob_calm, c(99.4, 98.9, 99.2, 97.0), 5e-2),
  check("Bornes hautes arrondies (4 déc.), doc §3", round(chain$p_max, 4),
        c(1.1675, 1.1620, 1.1613, 1.1538), 1e-9)
)

# Drapeaux dedans/dehors : recalcul contre le tableau §3.1 du document
flags <- chain %>%
  transmute(open_out  = out_of(open,  p_min, p_max), high_out = out_of(high, p_min, p_max),
            low_out   = out_of(low,   p_min, p_max), close_out = out_of(close, p_min, p_max))
doc_flags <- cbind(open_out  = c(FALSE, FALSE, FALSE, FALSE), high_out = c(FALSE, FALSE, FALSE, FALSE),
                   low_out   = c(TRUE, FALSE, TRUE, FALSE),   close_out = c(FALSE, FALSE, TRUE, FALSE))
flags_ok <- identical(unname(as.matrix(flags)), unname(doc_flags))
cat(sprintf("%-46s %s\n", "Drapeaux O/H/L/C dedans-dehors, doc §3.1", if (flags_ok) "[OK]" else "[ÉCART]"))
res <- c(res, flags_ok,
         identical(chain$inside_range, !flags$close_out))
cat(sprintf("%-46s %s\n", "inside_range (CSV) = clôture dans la bande",
            if (identical(chain$inside_range, !flags$close_out)) "[OK]" else "[ÉCART]"))

cat("\n-- Informatif --\n")
cat("Borne basse exacte, prévision 2 :", format(chain$p_min[2], digits = 9),
    "-> arrondi à 4 décimales :", round(chain$p_min[2], 4),
    "(le document écrit 1.1478 dans §3 et §3.1)\n")
cat("Dépassement exact du 16/09 (clôture sous la borne basse) :",
    format(chain$p_min[3] - chain$actual_price[3], digits = 4),
    "=", percent((chain$p_min[3] - chain$actual_price[3]) / chain$actual_price[3], accuracy = 0.001),
    "(le document écrit 0.0007 et 0.061 %)\n")
cat("Proceeds §6 : borne basse / haute (EUR 1 M, prévision 3) :",
    format(1e6 * chain$p_min[3], big.mark = ",", digits = 7), "/",
    format(1e6 * chain$p_max[3], big.mark = ",", digits = 7),
    "; clôture :", format(1e6 * chain$actual_price[3], big.mark = ",", digits = 7), "\n")
cat("Ouverture(t) = clôture(t-1) pour 15, 16, 17/09 :",
    all(abs(chain$open[2:4] - chain$actual_price[1:3]) < 1e-9), "\n")
cat("Indice base 100 de P(stress) :", round(100 * chain$prob_stress / chain$prob_stress[1]),
    "(les valeurs arrondies du document donneraient 100 / 183 / 133 / 500)\n")

# Quantification des bornes de Risk() : toutes les bornes (en % de rendement log)
# tombent sur un réseau régulier. Mesuré à partir de ces CSV : pas ~ 0,00678 %,
# décalage 0,3985 pas. Ce n'est pas du bruit Monte Carlo : c'est la résolution
# numérique de la fonction de répartition évaluée par Risk().
grid_step <- 0.00678
grid_off  <- 0.3985
bounds <- fan %>%
  left_join(select(chain, cutoff_date, cutoff_price), by = "cutoff_date") %>%
  transmute(lo = log(p_min / cutoff_price) * 100, hi = log(p_max / cutoff_price) * 100)
xs  <- c(bounds$lo, bounds$hi)
res_grid <- ((xs / grid_step - grid_off + 0.5) %% 1) - 0.5
cat(sprintf("Réseau des bornes de Risk() : pas %.5f %%, écart max au réseau = %.4f pas (%d bornes)\n",
            grid_step, max(abs(res_grid)), length(xs)))
if (max(abs(res_grid)) < 0.01) {
  cat("  -> Toutes les bornes sont sur le réseau : résolution numérique de Risk(),\n",
      "     pas du bruit d'échantillonnage. Les différences de largeur d'un pas\n",
      "     (~0,56 % de la largeur à 95 %) sont sous cette résolution.\n", sep = "")
}

cat(if (all(res)) "\n=> Tous les contrôles sont OK.\n" else
      "\n=> ATTENTION : au moins un écart. Vérifier avant d'utiliser les figures.\n")
cat("=======================================================\n\n")

# ==============================================================================
# FIGURE 01 — Bandes de confiance et chandelier réel, une prévision par panneau
#   Axe vertical commun aux 4 panneaux. Bandes 20/50/80/95 % à la date cible ;
#   chandelier OHLC réel par-dessus. Rouge = portion HORS de la bande 95 %.
#   Rappel : le modèle est calibré sur les clôtures ; la mèche montre ce que la
#   bande ne prétendait pas couvrir (voir §3.1 du document).
# ==============================================================================
closes <- bind_rows(
  daily %>% filter(Date <= min(chain$cutoff_date)) %>% select(Date, Close),
  chain %>% transmute(Date = target_date, Close = actual_price)
) %>% distinct(Date, .keep_all = TRUE) %>% arrange(Date)

panel_label <- function(i) {
  r <- chain[i, ]; f <- flags[i, ]
  paste0("Prévision ", r$forecast, " : ", format(r$cutoff_date, "%d/%m"), " \u2192 ",
         format(r$target_date, "%d/%m"), "\n",
         "clôture ", if (f$close_out) "HORS" else "dans", " la bande, plus bas ",
         if (f$low_out) "HORS" else "dans")
}
panel_levels <- vapply(seq_len(nrow(chain)), panel_label, character(1))
chain <- chain %>% mutate(panel = factor(panel_levels, levels = panel_levels))

hist_df <- map_dfr(seq_len(nrow(chain)), function(i) {
  closes %>% filter(Date <= chain$cutoff_date[i]) %>% tail(6) %>%
    mutate(panel = chain$panel[i])
})

half_band  <- 0.45   # demi-largeur des bandes (jours)
half_body  <- 0.16   # demi-largeur du corps du chandelier (jours)
lvl_sorted <- sort(unique(fan$confidence_level))
lvl_labels <- percent(lvl_sorted, accuracy = 1)

bands <- fan %>%
  left_join(select(chain, cutoff_date, panel), by = "cutoff_date") %>%
  mutate(xmin = target_date - half_band, xmax = target_date + half_band,
         level_f = factor(confidence_level, levels = lvl_sorted, labels = lvl_labels)) %>%
  arrange(desc(confidence_level))

lab95 <- bands %>% filter(confidence_level == 0.95) %>%
  select(panel, target_date, p_min, p_max) %>%
  pivot_longer(c(p_min, p_max), values_to = "p") %>%
  mutate(x = target_date + half_band + 0.2)

candle <- chain %>%
  mutate(dir = ifelse(close >= open, "up", "down"),
         xmin = target_date - half_body, xmax = target_date + half_body,
         ymin = pmin(open, close), ymax = pmax(open, close),
         close_col = ifelse(out_of(close, p_min, p_max), col_out, "white"),
         close_sz  = ifelse(out_of(close, p_min, p_max), 2.6, 1.8))

red_low  <- chain %>% filter(low  < p_min) %>% transmute(panel, x = target_date, y = low,  yend = p_min)
red_high <- chain %>% filter(high > p_max) %>% transmute(panel, x = target_date, y = high, yend = p_max)

# Valeur du plus bas / plus haut quand il sort de la bande 95 %
lab_ext <- bind_rows(
  chain %>% filter(low  < p_min) %>% transmute(panel, x = target_date - half_band - 0.2, y = low,
                                               lab = paste0("plus bas ", number(low, accuracy = 0.0001, decimal.mark = ","))),
  chain %>% filter(high > p_max) %>% transmute(panel, x = target_date - half_band - 0.2, y = high,
                                               lab = paste0("plus haut ", number(high, accuracy = 0.0001, decimal.mark = ",")))
)

g1 <- ggplot() +
  geom_line(data = hist_df, aes(x = Date, y = Close), color = "grey30", linewidth = 0.5) +
  geom_point(data = hist_df, aes(x = Date, y = Close), size = 1.2, color = "grey30") +
  geom_rect(data = bands,
            aes(xmin = xmin, xmax = xmax, ymin = p_min, ymax = p_max, alpha = level_f),
            fill = col_band) +
  geom_segment(data = chain, aes(x = target_date, xend = target_date, y = low, yend = high),
               color = "black", linewidth = 0.5) +
  geom_segment(data = red_low,  aes(x = x, xend = x, y = y, yend = yend), color = col_out, linewidth = 1.3) +
  geom_segment(data = red_high, aes(x = x, xend = x, y = y, yend = yend), color = col_out, linewidth = 1.3) +
  geom_rect(data = candle,
            aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = dir),
            color = "black", linewidth = 0.4) +
  geom_point(data = candle, aes(x = target_date, y = close),
             shape = 21, fill = candle$close_col, color = "black", size = candle$close_sz) +
  geom_text(data = lab95, aes(x = x, y = p, label = number(p, accuracy = 0.0001, decimal.mark = ",")),
            hjust = 0, size = 2.5, color = "grey20") +
  geom_text(data = lab_ext, aes(x = x, y = y, label = lab), hjust = 1, size = 2.5, color = col_out) +
  facet_wrap(~panel, nrow = 2, scales = "free_x") +
  scale_fill_manual(values = c(up = "white", down = "black"), guide = "none") +
  scale_alpha_manual(values = setNames(c(0.60, 0.42, 0.28, 0.16), lvl_labels),
                     name = "Niveau de confiance",
                     guide = guide_legend(override.aes = list(fill = col_band))) +
  scale_x_date(date_labels = "%d/%m", expand = expansion(add = c(0.4, 2.2))) +
  scale_y_continuous(labels = number_format(accuracy = 0.001, decimal.mark = ",")) +
  labs(title = "Fourchettes à 1 jour et chandelier réel \u2014 semaine du 14 au 17 septembre 2026",
       subtitle = "Axe vertical commun aux quatre panneaux. Rouge : portion hors de la bande à 95 %.",
       caption = paste0("Bandes 20/50/80/95 % du modèle (calibré sur les clôtures). Chandelier : corps ouverture-clôture\n",
                        "(blanc = hausse, noir = baisse), mèche plus bas-plus haut (Pound Sterling Live).\n",
                        "Point : clôture (rouge si hors de la bande 95 %)."),
       x = NULL, y = "EUR/USD") +
  theme(legend.position = "bottom",
        plot.subtitle = element_text(size = 9.5),
        plot.caption = element_text(size = 7.5, hjust = 0, color = "grey30"),
        strip.text = element_text(face = "bold", size = 9.5))

save_fig(g1, "01_rolling_bands_and_candles.png", width = 9, height = 7)

# ==============================================================================
# FIGURE 02 — Risque perçu vs largeur de la fourchette (§5.3), base 100
# ==============================================================================
idx <- chain %>%
  transmute(target_date,
            `Probabilité de stress` = 100 * prob_stress / prob_stress[1],
            `Largeur de la fourchette à 95 %` = 100 * range_width_pct / range_width_pct[1]) %>%
  pivot_longer(-target_date, names_to = "serie", values_to = "indice") %>%
  mutate(jour = factor(format(target_date, "%d/%m"), levels = format(chain$target_date, "%d/%m")))

quantum_pct <- 100 * grid_step / (100 * chain$range_width_pct[1])   # pas / largeur, en %

g2 <- ggplot(idx, aes(x = jour, y = indice, color = serie, group = serie)) +
  geom_hline(yintercept = 100, linetype = "dotted", color = "grey60") +
  geom_line(linewidth = 0.8) +
  geom_point(size = 3) +
  geom_text(aes(label = number(indice, accuracy = 1),
                vjust = ifelse(serie == "Probabilité de stress", -1.1, 2.1)),
            size = 3.3, show.legend = FALSE) +
  scale_color_manual(values = c("Probabilité de stress" = col_out,
                                "Largeur de la fourchette à 95 %" = "grey30"), name = NULL) +
  scale_y_continuous(limits = c(50, 580), breaks = seq(100, 500, 100)) +
  labs(title = paste0("P(stress) \u00d7", number(chain$prob_stress[4] / chain$prob_stress[1], accuracy = 0.1, decimal.mark = ","),
                      ", largeur de la fourchette +",
                      number(100 * (chain$range_width_pct[4] / chain$range_width_pct[1] - 1), accuracy = 0.1, decimal.mark = ","), " %"),
       subtitle = paste0("Indice base 100 = prévision du 14/09. P(stress) : ",
                         number(100 * chain$prob_stress[1], accuracy = 0.01, decimal.mark = ","), " % \u2192 ",
                         number(100 * chain$prob_stress[4], accuracy = 0.01, decimal.mark = ","), " %\n",
                         "Largeur à 95 % : ",
                         number(100 * chain$range_width_pct[1], accuracy = 0.001, decimal.mark = ","), " % \u2192 ",
                         number(100 * chain$range_width_pct[4], accuracy = 0.001, decimal.mark = ","), " %"),
       caption = paste0("Jour cible en abscisse. Les bornes de Risk() sont calculées sur une grille de ",
                        number(grid_step, accuracy = 0.00001, decimal.mark = ","), " point de rendement\n",
                        "(\u2248 ", number(quantum_pct, accuracy = 0.1, decimal.mark = ","),
                        " % de la largeur) : l'écart de largeur entre le 15 et le 16/09 est de l'ordre d'un pas."),
       x = "Jour cible", y = "Indice (base 100 = 14/09)") +
  theme(legend.position = "bottom",
        plot.subtitle = element_text(size = 9.5),
        plot.caption = element_text(size = 7.5, hjust = 0, color = "grey30"))

save_fig(g2, "02_stress_probability_vs_width.png", height = 4.6)

# ==============================================================================
cat("Terminé \u2014", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")
