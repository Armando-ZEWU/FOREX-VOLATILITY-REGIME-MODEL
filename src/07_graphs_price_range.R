# ==============================================================================
# Graphs — Price_Range.md
# Génère les 2 figures retenues pour le document Price_Range.md
# Sortie : PNG, 300 dpi, dans graphs/Price_Range_plot/
#
# Entrées :
#   data/processed/ms_garch_fan_chart_inputs.csv             mélange, 4 niveaux
#   data/processed/ms_garch_regime_conditional_forecast.csv  calme / stress, 4 niveaux
#   data/raw/eurusd_daily.csv                                historique des clôtures (Date, Close)
#
# Mapping figure -> section du document :
#   01  §8            fan chart, 3 panneaux (mélange / calme / stress)
#   02  §8            rapport des largeurs stress/calme selon le niveau
#
# Non générés (volontairement) :
#   §7  prix réel du 14/09 vs fourchette : une seule observation, traitée avec
#       rolling_test.md (11 -> 17 septembre)
#   §6  exemple 1 M EUR : chiffres déjà dans le texte
#   §3.1 quantile Student-t : un seul nombre
#
# CONVERSION RETOUR -> PRIX : P = last_price * exp(q / 100), q en % de
# rendement log. Une conversion linéaire P = last_price * (1 + q/100) donne les
# mêmes prix à 4 décimales sur ces valeurs.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ---- 0. Chemins ---------------------------------------------------------
raw_dir       <- here("data", "raw")
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Price_Range_plot")
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

col_mix <- "grey35"
col_r1  <- "steelblue4"   # calme     (même palette que 06_graphs_ms_garch.R)
col_r2  <- "firebrick"    # stress

# ---- 1. Chargement -------------------------------------------------------
fan <- read_csv(file.path(processed_dir, "ms_garch_fan_chart_inputs.csv"),
                col_types = cols(confidence_level = col_double(),
                                 alpha_low = col_double(), alpha_high = col_double(),
                                 return_q_low = col_double(), return_q_high = col_double(),
                                 last_date = col_date(), last_price = col_double()))

reg <- read_csv(file.path(processed_dir, "ms_garch_regime_conditional_forecast.csv"),
                col_types = cols(confidence_level = col_double(), regime = col_character(),
                                 return_q_low = col_double(), return_q_high = col_double(),
                                 last_date = col_date(), last_price = col_double()))

daily <- read_csv(file.path(raw_dir, "eurusd_daily.csv"),
                  col_types = cols(Date = col_date(), Close = col_double()))

last_date  <- unique(fan$last_date)
last_price <- unique(fan$last_price)
stopifnot(length(last_date) == 1, length(last_price) == 1,
          all(reg$last_date == last_date), all(reg$last_price == last_price))

# ---- 2. Bandes en prix ---------------------------------------------------
to_price <- function(q, p0) p0 * exp(q / 100)

panel_levels <- c("Mélange (opérationnel)", "Régime 1 (calme)", "Régime 2 (stress)")

bands <- bind_rows(
  fan %>% transmute(panel = "Mélange (opérationnel)", level = confidence_level,
                    q_low = return_q_low, q_high = return_q_high),
  reg %>% transmute(panel = recode(regime, "1_calm" = "Régime 1 (calme)",
                                           "2_stress" = "Régime 2 (stress)"),
                    level = confidence_level,
                    q_low = return_q_low, q_high = return_q_high)
) %>%
  mutate(p_low  = to_price(q_low,  last_price),
         p_high = to_price(q_high, last_price),
         width_pct = 100 * (p_high - p_low) / last_price,
         panel = factor(panel, levels = panel_levels))

get_col <- function(p, col) bands %>% filter(panel == p) %>% arrange(level) %>% pull({{ col }})

# ---- 3. CONTRÔLE (s'imprime dans la console R) ---------------------------
check <- function(label, got, doc, tol) {
  ok <- all(abs(got - doc) <= tol)
  cat(sprintf("%-42s obtenu: %-30s doc: %-30s [%s]\n", label,
              paste(round(got, 4), collapse = " / "),
              paste(doc, collapse = " / "),
              if (ok) "OK" else "ÉCART"))
  ok
}

cat("\n================ CONTRÔLE PRICE_RANGE ================\n")
close_at_last <- daily$Close[daily$Date == last_date]
res <- c(
  check("Clôture eurusd_daily.csv = last_price", close_at_last, last_price, 1e-6),
  check("Largeurs mélange (%), doc §8",  get_col("Mélange (opérationnel)", width_pct),
        c(0.136, 0.366, 0.732, 1.220), 6e-4),
  check("Largeurs calme (%), doc §8",    get_col("Régime 1 (calme)", width_pct),
        c(0.135, 0.365, 0.726, 1.212), 6e-4),
  check("Largeurs stress (%), doc §8",   get_col("Régime 2 (stress)", width_pct),
        c(0.282, 0.754, 1.454, 2.282), 6e-4),
  check("Ratio stress/calme, doc §8",
        get_col("Régime 2 (stress)", width_pct) / get_col("Régime 1 (calme)", width_pct),
        c(2.09, 2.07, 2.00, 1.88), 6e-3)
)
r95 <- function(p) bands %>% filter(panel == p, level == 0.95) %>% select(p_low, p_high) %>% unlist()
res <- c(res,
  check("Fourchette 95% mélange, doc §3", r95("Mélange (opérationnel)"), c(1.1533, 1.1675), 1e-4),
  check("Fourchette 95% calme, doc §4.2", r95("Régime 1 (calme)"),       c(1.1534, 1.1675), 1e-4),
  check("Fourchette 95% stress, doc §4.2", r95("Régime 2 (stress)"),     c(1.1472, 1.1737), 1e-4)
)
nested_ok <- all(sapply(panel_levels, function(p) {
  all(diff(get_col(p, p_low)) < 0) && all(diff(get_col(p, p_high)) > 0)
}))
cat(sprintf("%-42s %s\n", "Bandes emboîtées 20 ⊂ 50 ⊂ 80 ⊂ 95", if (nested_ok) "[OK]" else "[ÉCART]"))

cat("\n-- Informatif --\n")
mid <- (fan$return_q_low + fan$return_q_high) / 2
cat("Centre du mélange (q_low+q_high)/2, par niveau :", signif(mid, 6), "\n")
if (diff(range(mid)) < 1e-9) {
  cat("  -> IDENTIQUE à tous les niveaux : décalage de position constant\n",
      "    (pas du bruit d'échantillonnage, qui varierait d'un niveau à l'autre).\n", sep = "")
}
cat(if (all(res) && nested_ok) "\n=> Tous les contrôles sont OK.\n" else
      "\n=> ATTENTION : au moins un écart. Vérifier avant d'utiliser les figures.\n")
cat("======================================================\n\n")

# ==============================================================================
# FIGURE 01 — Fan chart à 3 panneaux (§8)
#   Même axe vertical dans les trois panneaux : la comparaison des largeurs est
#   directe. Prévision à UN pas : les bandes sont posées à la date de prévision,
#   sans interpolation entre la dernière clôture et la prévision.
# ==============================================================================
n_hist <- 30
hist_df <- daily %>% filter(Date <= last_date) %>% arrange(Date) %>% tail(n_hist)

wd <- as.integer(format(last_date, "%u"))          # 1 = lundi ... 7 = dimanche
forecast_date <- last_date + if (wd == 5) 3L else if (wd == 6) 2L else 1L
half_w <- 0.8                                      # demi-largeur des bandes (jours)

lvl_labels <- percent(sort(unique(bands$level)), accuracy = 1)

fan_plot <- bands %>%
  mutate(xmin = forecast_date - half_w, xmax = forecast_date + half_w,
         level_f = factor(level, levels = sort(unique(level)), labels = lvl_labels)) %>%
  arrange(desc(level))                             # bande la plus large dessinée en premier

lab95 <- bands %>% filter(level == 0.95) %>%
  select(panel, p_low, p_high) %>%
  pivot_longer(c(p_low, p_high), values_to = "p") %>%
  mutate(x = forecast_date + half_w + 0.4)

g1 <- ggplot() +
  geom_hline(yintercept = last_price, linetype = "dotted", color = "grey55") +
  geom_line(data = hist_df, aes(x = Date, y = Close), color = "grey20", linewidth = 0.5) +
  geom_point(data = tail(hist_df, 1), aes(x = Date, y = Close), size = 1.8, color = "grey10") +
  geom_rect(data = fan_plot,
            aes(xmin = xmin, xmax = xmax, ymin = p_low, ymax = p_high,
                fill = panel, alpha = level_f)) +
  geom_text(data = lab95, aes(x = x, y = p, label = number(p, accuracy = 0.0001, decimal.mark = ",")),
            hjust = 0, size = 2.6, color = "grey20") +
  facet_wrap(~panel, nrow = 1) +
  scale_fill_manual(values = c("Mélange (opérationnel)" = col_mix,
                               "Régime 1 (calme)" = col_r1,
                               "Régime 2 (stress)" = col_r2), guide = "none") +
  scale_alpha_manual(values = setNames(c(0.90, 0.65, 0.45, 0.30), lvl_labels),
                     name = "Niveau de confiance",
                     guide = guide_legend(override.aes = list(fill = "grey30"))) +
  scale_x_date(breaks = seq(forecast_date, by = "-2 weeks", length.out = 4),
               date_labels = "%d/%m",
               limits = c(min(hist_df$Date), forecast_date + 9),
               expand = expansion(mult = 0.01)) +
  scale_y_continuous(labels = number_format(accuracy = 0.001, decimal.mark = ",")) +
  labs(title = "Fourchette EUR/USD à 1 jour \u2014 bandes de confiance 20 / 50 / 80 / 95 %",
       subtitle = paste0("Dernière clôture ", format(last_date, "%d/%m/%Y"), " : ",
                         number(last_price, accuracy = 0.0001, decimal.mark = ","),
                         " ; prévision pour le ", format(forecast_date, "%d/%m/%Y"),
                         ". Même axe vertical dans les trois panneaux."),
       x = NULL, y = "EUR/USD") +
  theme(legend.position = "bottom",
        plot.subtitle = element_text(size = 9.5),
        strip.text = element_text(face = "bold"))

save_fig(g1, "01_fan_chart_three_panels.png", width = 9, height = 4.4)

# ==============================================================================
# FIGURE 02 — Rapport de largeurs stress / calme selon le niveau (§8)
#   Ligne pointillée : rapport des sigma prévus (doc §4.2 : 0,5769 / 0,3033).
#   Si les deux régimes avaient la même forme de loi, le rapport serait
#   constant et égal à cette valeur. Les écarts mesurent l'effet de forme.
# ==============================================================================
sigma_calm   <- 0.3033
sigma_stress <- 0.5769
vol_ratio    <- sigma_stress / sigma_calm

lv <- sort(unique(bands$level))
ratio_df <- tibble(
  level = factor(lv, levels = lv, labels = percent(lv, accuracy = 1)),
  ratio = get_col("Régime 2 (stress)", width_pct) / get_col("Régime 1 (calme)", width_pct)
)

g2 <- ggplot(ratio_df, aes(x = level, y = ratio, group = 1)) +
  geom_hline(yintercept = vol_ratio, linetype = "dashed", color = "grey40") +
  geom_line(color = col_r2, linewidth = 0.7) +
  geom_point(color = col_r2, size = 3) +
  geom_text(aes(label = number(ratio, accuracy = 0.01, decimal.mark = ","),
                vjust = ifelse(ratio < vol_ratio, 2.2, -1.2)), size = 3.4) +
  annotate("text", x = 1, y = vol_ratio, hjust = 0, vjust = 1.7, size = 3,
           color = "grey30",
           label = paste0("Rapport des \u03c3 prévus : ",
                          number(vol_ratio, accuracy = 0.01, decimal.mark = ","))) +
  scale_y_continuous(limits = c(1.75, 2.20), breaks = seq(1.8, 2.2, 0.1),
                     labels = number_format(accuracy = 0.1, decimal.mark = ",")) +
  labs(title = "Largeur stress / largeur calme selon le niveau de confiance",
       subtitle = paste0("Le rapport serait constant et égal au rapport des \u03c3 prévus\n",
                         "si les deux régimes avaient la même forme de loi"),
       x = "Niveau de confiance", y = "Largeur stress / largeur calme") +
  theme(plot.subtitle = element_text(size = 9.5))

save_fig(g2, "02_width_ratio_stress_calm.png", height = 4.0)

# ==============================================================================
cat("Terminé \u2014", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")
