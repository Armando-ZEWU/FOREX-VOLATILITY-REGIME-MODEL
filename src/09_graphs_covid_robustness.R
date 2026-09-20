# ==============================================================================
# Graphs — Covid_Robustness_Test.md
# Génère les 3 figures retenues pour le document Covid_Robustness_Test.md
# Sortie : PNG, 300 dpi, dans graphs/Covid_Robustness_Test_plot/
#
# Entrées (data/processed/) :
#   covid_full_comparison_table.csv   84 lignes : bande 95 %, taux FRED, OHLC PSL, P(stress)
#   covid_robustness_fan_data.csv     bandes 20/50/80/95 % par jour
#   covid_robustness_result.csv       84 prévisions (utilisé pour recouper la table)
#   (L'OHLC brut data/raw/eurusd_ohlc_2020_covid.csv n'est pas relu : la table de
#    comparaison le contient déjà, vérifié identique pour High et Low.)
#
# Mapping figure -> section du document :
#   01  §7   bandes 20/50/80/95 % et chandeliers réels, 84 jours
#   02  §4   P(stress) au moment de la prévision + les 7 sorties, groupes A et B
#   03  §3, §5  taux de sorties de la bande 95 % avec IC exacts (Clopper-Pearson)
#
# CE QUE LE MARQUEUR REPRÉSENTE : le taux FRED (DEXUSEU) est, d'après la page de la
# série, le taux acheteur de MIDI à New York (H.10), pas une clôture. Le modèle est
# calibré et testé sur ce taux ; l'OHLC de Pound Sterling Live couvre la journée
# entière. Le losange de la figure 01 est donc le taux FRED, pas la clôture de la bougie.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Covid_Robustness_Test_plot")
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

col_band <- "steelblue3"   # même famille de couleurs que 08_graphs_rolling_test.R
col_out  <- "firebrick"    # hors de la bande 95 %
col_A    <- "darkorange2"  # groupe A : régime pas encore réagi
col_B    <- "firebrick"    # groupe B : régime déjà en stress

out_of <- function(x, lo, hi) x < lo | x > hi

# ---- 1. Chargement -------------------------------------------------------
comp <- read_csv(file.path(processed_dir, "covid_full_comparison_table.csv"),
                 col_types = cols_only(target_date = col_date(), p_min = col_double(),
                                       p_max = col_double(), actual_price = col_double(),
                                       Open = col_double(), High = col_double(),
                                       Low = col_double(), Close = col_double(),
                                       prob_stress = col_double()))

res <- read_csv(file.path(processed_dir, "covid_robustness_result.csv"),
                col_types = cols_only(target_date = col_date(), p_min = col_double(),
                                      p_max = col_double(), actual_price = col_double(),
                                      prob_stress = col_double()))

fan <- read_csv(file.path(processed_dir, "covid_robustness_fan_data.csv"),
                col_types = cols(target_date = col_date(), confidence_level = col_double(),
                                 p_min = col_double(), p_max = col_double(),
                                 actual_price = col_double()))

d <- comp %>%
  arrange(target_date) %>%
  mutate(i = row_number(),
         close_out = out_of(actual_price, p_min, p_max),
         close_dir = case_when(actual_price > p_max ~ "Upper",
                               actual_price < p_min ~ "Lower", TRUE ~ "inside"),
         breach_pct = case_when(actual_price > p_max ~ (actual_price - p_max) / actual_price * 100,
                                actual_price < p_min ~ (p_min - actual_price) / actual_price * 100,
                                TRUE ~ 0),
         high_out = High > p_max,
         low_out  = Low  < p_min,
         any_out  = close_out | high_out | low_out)
n <- nrow(d)

# ---- 2. CONTRÔLE (s'imprime dans la console R) ---------------------------
check <- function(label, got, doc, tol) {
  ok <- all(abs(got - doc) <= tol)
  cat(sprintf("%-46s obtenu: %-38s doc: %-38s [%s]\n", label,
              paste(round(got, 3), collapse = " / "),
              paste(doc, collapse = " / "),
              if (ok) "OK" else "ÉCART"))
  ok
}
check_txt <- function(label, got, doc) {
  ok <- identical(got, doc)
  cat(sprintf("%-46s obtenu: %-38s doc: %-38s [%s]\n", label,
              paste(got, collapse = " / "), paste(doc, collapse = " / "),
              if (ok) "OK" else "ÉCART"))
  ok
}

cat("\n================ CONTRÔLE COVID_ROBUSTNESS ================\n")
b <- d %>% filter(close_out)
p_one <- binom.test(sum(d$close_out), n, p = 0.05, alternative = "greater")$p.value
p_two <- binom.test(sum(d$close_out), n, p = 0.05)$p.value

res_ok <- c(
  check("Fichiers alignés (dates, p_min, p_max, taux FRED)",
        c(as.numeric(all(res$target_date == d$target_date)),
          max(abs(res$p_min - d$p_min)), max(abs(res$p_max - d$p_max)),
          max(abs(res$actual_price - d$actual_price))), c(1, 0, 0, 0), 1e-12),
  check("Nombre de jours", n, 84, 0),
  check("Couverts / total (FRED)", c(n - sum(d$close_out), n), c(77, 84), 0),
  check("Sorties attendues sous 95 %", 0.05 * n, 4.2, 1e-9),
  check("Binomial unilatéral p, bilatéral p", c(p_one, p_two), c(0.127, 0.200), 6e-4),
  check("High > borne haute (jours)", sum(d$high_out), 12, 0),
  check("Low < borne basse (jours)", sum(d$low_out), 7, 0),
  check("Jours uniques hors bande (C ou H ou L)", sum(d$any_out), 19, 0),
  check("Taux (%) clôture / High / Low / unique",
        100 * c(sum(d$close_out), sum(d$high_out), sum(d$low_out), sum(d$any_out)) / n,
        c(8.3, 14.3, 8.3, 22.6), 0.06),
  check("Rapport unique / clôture (« 2,7x »)", sum(d$any_out) / sum(d$close_out), 2.7, 0.02),
  check_txt("Dates des 7 sorties (clôture FRED)", format(b$target_date),
            c("2020-02-21", "2020-02-27", "2020-03-02", "2020-03-06",
              "2020-03-12", "2020-03-17", "2020-03-26")),
  check_txt("Directions des 7 sorties", b$close_dir,
            c("Upper", "Upper", "Upper", "Upper", "Lower", "Lower", "Upper")),
  check("Taille des sorties (%), tableau §4", b$breach_pct,
        c(0.02, 0.31, 0.90, 0.09, 0.63, 0.30, 0.44), 6e-3),
  check("P(stress) à la prévision (%), tableau §4", 100 * b$prob_stress,
        c(0.3, 0.3, 2.5, 49.3, 98.7, 99.2, 98.4), 6e-2)
)

cat("\n-- Informatif --\n")
gap <- function(x) 100 * (x$actual_price - x$Close) / x$Close
calm   <- d %>% filter(target_date <  as.Date("2020-02-24"))
crisis <- d %>% filter(target_date >= as.Date("2020-02-24"))
cat(sprintf("Écart taux FRED (midi) vs clôture PSL : calme (n=%d) |écart| moyen %.3f %%, écart-type %.3f %% ;\n",
            nrow(calm), mean(abs(gap(calm))), sd(gap(calm))))
cat(sprintf("                                        crise (n=%d) |écart| moyen %.3f %%, écart-type %.3f %%, max %.3f %%\n",
            nrow(crisis), mean(abs(gap(crisis))), sd(gap(crisis)), max(abs(gap(crisis)))))
psl_out <- out_of(d$Close, d$p_min, d$p_max)
cat("Sorties si l'on utilise la clôture PSL au lieu du taux FRED :", sum(psl_out),
    "(dont", sum(psl_out & d$close_out), "en commun avec les 7 sorties FRED)\n")
st <- d %>% filter(prob_stress > 0.95)
cat(sprintf("Jours à P(stress) > 95 %% : %d, sorties FRED : %d (%.1f %%)\n",
            nrow(st), sum(st$close_out), 100 * mean(st$close_out)))
fan_ratio <- fan %>% left_join(select(d, target_date, prob_stress), by = "target_date") %>%
  filter(confidence_level %in% c(0.2, 0.95), prob_stress > 0.95) %>%
  mutate(w = p_max - p_min) %>% select(target_date, confidence_level, w) %>%
  pivot_wider(names_from = confidence_level, values_from = w, names_prefix = "w")
cat(sprintf("Rapport largeur 95 %% / largeur 20 %% (jours à P(stress) > 95 %%) : %.2f  (Normale : %.2f)\n",
            mean(fan_ratio$w0.95 / fan_ratio$w0.2), qnorm(0.975) / qnorm(0.6)))
qstd <- function(nu, p = 0.975) qt(p, nu) * sqrt((nu - 2) / nu)
cat(sprintf("Quantile 95 %% standardisé : nu = 71,73 -> %.3f ; nu = 7,07 -> %.3f (+%.1f %%)\n",
            qstd(71.73), qstd(7.07), 100 * (qstd(7.07) / qstd(71.73) - 1)))
cat(sprintf("Sorties du groupe B en multiples de la demi-largeur 95 %% (approx. Normale) : %s\n",
            paste(round(with(d %>% filter(close_out, prob_stress > 0.95),
                             abs(log(actual_price / ((p_min + p_max) / 2))) /
                               (log(p_max / p_min) / 2) * 1.96), 2), collapse = " / ")))
cat(if (all(res_ok)) "\n=> Tous les contrôles du document sont OK.\n" else
      "\n=> ATTENTION : au moins un écart. Vérifier avant d'utiliser les figures.\n")
cat("===========================================================\n\n")

# ==============================================================================
# FIGURE 01 — Bandes 20/50/80/95 % et chandeliers réels (§7)
#   Abscisse : jours de bourse consécutifs (les week-ends ne créent pas de trous).
#   Bougie : OHLC Pound Sterling Live. Losange : taux FRED de midi (base du test).
#   Rouge : portion de mèche hors de la bande 95 %, ou losange hors de la bande.
# ==============================================================================
lvl_sorted <- sort(unique(fan$confidence_level))
lvl_labels <- percent(lvl_sorted, accuracy = 1)

bands <- fan %>%
  left_join(select(d, target_date, i), by = "target_date") %>%
  mutate(xmin = i - 0.42, xmax = i + 0.42,
         level_f = factor(confidence_level, levels = lvl_sorted, labels = lvl_labels)) %>%
  arrange(desc(confidence_level))

half_body <- 0.28
candle <- d %>%
  mutate(dir = ifelse(Close >= Open, "up", "down"),
         ymin = pmin(Open, Close), ymax = pmax(Open, Close),
         mk_fill = ifelse(close_out, col_out, "darkorange"))

red_low  <- d %>% filter(Low  < p_min) %>% transmute(i, y = Low,  yend = p_min)
red_high <- d %>% filter(High > p_max) %>% transmute(i, y = High, yend = p_max)

brk <- seq(1, n, by = 10)
lab <- format(d$target_date[brk], "%d/%m")

g1 <- ggplot() +
  geom_rect(data = bands,
            aes(xmin = xmin, xmax = xmax, ymin = p_min, ymax = p_max, alpha = level_f),
            fill = col_band) +
  geom_segment(data = d, aes(x = i, xend = i, y = Low, yend = High),
               color = "black", linewidth = 0.25) +
  geom_segment(data = red_low,  aes(x = i, xend = i, y = y, yend = yend), color = col_out, linewidth = 0.7) +
  geom_segment(data = red_high, aes(x = i, xend = i, y = y, yend = yend), color = col_out, linewidth = 0.7) +
  geom_rect(data = candle,
            aes(xmin = i - half_body, xmax = i + half_body, ymin = ymin, ymax = ymax, fill = dir),
            color = "black", linewidth = 0.15) +
  geom_point(data = candle, aes(x = i, y = actual_price),
             shape = 23, fill = candle$mk_fill, color = "black", size = 1.5, stroke = 0.25) +
  scale_fill_manual(values = c(up = "white", down = "black"), guide = "none") +
  scale_alpha_manual(values = setNames(c(0.60, 0.42, 0.28, 0.16), lvl_labels),
                     name = "Niveau de confiance",
                     guide = guide_legend(override.aes = list(fill = col_band))) +
  scale_x_continuous(breaks = brk, labels = lab, expand = expansion(add = 1)) +
  scale_y_continuous(labels = number_format(accuracy = 0.01, decimal.mark = ",")) +
  labs(title = "Test COVID hors échantillon \u2014 bandes du modèle pré-2020 et chandeliers réels",
       subtitle = "84 jours de bourse (2 janvier \u2013 30 avril 2020), paramètres figés à fin 2019",
       caption = paste0("Bandes 20/50/80/95 %. Chandelier : corps ouverture-clôture (blanc = hausse, noir = baisse), ",
                        "mèche plus bas-plus haut (Pound Sterling Live).\n",
                        "Losange : taux FRED DEXUSEU (midi, New York), base du test de couverture ; rouge = hors de la bande à 95 %. ",
                        "Rouge sur la mèche : portion hors bande."),
       x = NULL, y = "EUR/USD") +
  theme(legend.position = "bottom",
        plot.subtitle = element_text(size = 9.5),
        plot.caption = element_text(size = 7.5, hjust = 0, color = "grey30"))

save_fig(g1, "01_covid_bands_and_candles.png", width = 11, height = 5.6)

# ==============================================================================
# FIGURE 02 — P(stress) au moment de la prévision et les 7 sorties (§4)
#   Groupe A : P(stress) < 50 %  (le régime n'a pas encore réagi)
#   Groupe B : P(stress) > 95 %  (le régime a réagi, la bande a quand même été dépassée)
# ==============================================================================
grp_lab <- c(A = "Groupe A : régime pas encore réagi (P(stress) < 50 %)",
             B = "Groupe B : régime déjà en stress (P(stress) > 95 %)")

br <- d %>% filter(close_out) %>%
  mutate(group = case_when(prob_stress < 0.5 ~ "A", prob_stress > 0.95 ~ "B", TRUE ~ NA_character_),
         group_f = factor(grp_lab[group], levels = grp_lab),
         dir_f = factor(ifelse(close_dir == "Upper", "Sortie par le haut", "Sortie par le bas"),
                        levels = c("Sortie par le haut", "Sortie par le bas")),
         lab = format(target_date, "%d/%m"),
         # placement manuel des étiquettes : verticales au-dessus (A) ou en dessous (B),
         # horizontale à gauche pour 06/03 (le point est sur la montée de la courbe)
         is_0603 = target_date == as.Date("2020-03-06"),
         angle = ifelse(is_0603, 0, 90),
         hj    = ifelse(group == "B" | is_0603, 1, 0),
         dx    = ifelse(is_0603, -1, 0),
         dy    = case_when(group == "B" ~ -0.05, is_0603 ~ 0.03, TRUE ~ 0.05))

g2 <- ggplot(d, aes(x = i, y = prob_stress)) +
  geom_area(fill = col_out, alpha = 0.18) +
  geom_line(color = "grey35", linewidth = 0.5) +
  geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey45") +
  geom_point(data = br, aes(color = group_f, fill = group_f, shape = dir_f), size = 3.2) +
  geom_text(data = br, aes(x = i + dx, y = prob_stress + dy, label = lab, color = group_f,
                           angle = angle, hjust = hj),
            size = 3.1, show.legend = FALSE) +
  scale_color_manual(values = setNames(c(col_A, col_B), grp_lab), name = NULL) +
  scale_fill_manual(values = setNames(c(col_A, col_B), grp_lab), guide = "none") +
  scale_shape_manual(values = c("Sortie par le haut" = 24, "Sortie par le bas" = 25), name = NULL) +
  guides(color = guide_legend(order = 1, override.aes = list(shape = 16)),
         shape = guide_legend(order = 2, override.aes = list(fill = "grey60", color = "grey30"))) +
  scale_x_continuous(breaks = brk, labels = lab, expand = expansion(add = 1)) +
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(-0.04, 1.06)) +
  labs(title = "Probabilité de stress au moment de la prévision et sorties de la bande à 95 %",
       subtitle = "Les sept sorties du taux FRED hors de la bande à 95 % ; la forme du triangle indique le sens de la sortie",
       x = NULL, y = "P(régime de stress)") +
  theme(legend.position = "bottom", legend.box = "vertical",
        legend.spacing.y = unit(0, "pt"),
        plot.subtitle = element_text(size = 9.5))

save_fig(g2, "02_stress_probability_and_breaches.png", width = 9, height = 4.6)

# ==============================================================================
# FIGURE 03 — Taux de sorties de la bande 95 % et incertitude (§3, §5)
#   IC exacts de Clopper-Pearson à 95 %. Seule la première ligne est comparable au
#   seuil nominal de 5 % : le modèle est calibré sur le taux FRED de midi, alors que
#   High/Low couvrent la journée entière.
# ==============================================================================
rate_df <- tibble(
  mesure = c("Taux FRED (midi) hors bande",
             "High > borne haute (PSL)",
             "Low < borne basse (PSL)",
             "Au moins un des trois"),
  x = c(sum(d$close_out), sum(d$high_out), sum(d$low_out), sum(d$any_out))
) %>%
  mutate(rate = x / n,
         lo = map_dbl(x, ~ binom.test(.x, n)$conf.int[1]),
         hi = map_dbl(x, ~ binom.test(.x, n)$conf.int[2]),
         lab = paste0(x, "/", n, " (", number(100 * rate, accuracy = 0.1, decimal.mark = ","), " %)"),
         mesure = factor(mesure, levels = rev(mesure)),
         comparable = c(TRUE, FALSE, FALSE, FALSE))

g3 <- ggplot(rate_df, aes(x = rate, y = mesure, color = comparable)) +
  geom_vline(xintercept = 0.05, linetype = "dashed", color = "grey40") +
  geom_segment(aes(x = lo, xend = hi, yend = mesure), linewidth = 1) +
  geom_point(size = 3.2) +
  geom_text(aes(label = lab), vjust = -1.2, size = 3.2, color = "grey15") +
  annotate("text", x = 0.05, y = 4.45, label = "seuil nominal 5 %", hjust = -0.05, size = 3, color = "grey30") +
  scale_color_manual(values = c(`TRUE` = col_out, `FALSE` = "grey45"), guide = "none") +
  scale_x_continuous(labels = percent_format(accuracy = 1), limits = c(0, 0.36),
                     breaks = seq(0, 0.35, 0.05)) +
  labs(title = "Sorties de la bande à 95 % sur 84 jours (IC exacts à 95 %)",
       subtitle = paste0("Test binomial unilatéral (H1 : taux > 5 %) sur le taux FRED : p = ",
                         number(p_one, accuracy = 0.001, decimal.mark = ","),
                         " (bilatéral : ", number(p_two, accuracy = 0.001, decimal.mark = ","), ")"),
       caption = paste0("Seule la première ligne est comparable au seuil nominal de 5 % : le modèle est calibré sur le taux FRED de midi,\n",
                        "alors que High et Low (Pound Sterling Live) couvrent la journée entière."),
       x = "Part des 84 jours", y = NULL) +
  theme(plot.title.position = "plot", plot.caption.position = "plot",
        plot.subtitle = element_text(size = 9.5),
        plot.caption = element_text(size = 7.5, hjust = 0, color = "grey30"))

save_fig(g3, "03_breach_rates_with_ci.png", width = 8.5, height = 4.2)

# ==============================================================================
cat("Terminé \u2014", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")
