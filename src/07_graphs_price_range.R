# ==============================================================================
# Graphs — Price_Range.md
# Génère les 5 figures identifiées pour ce document.
# Sortie : PNG, 300 dpi, dans graphs/Price_range_plot/
#
# Architecture (identique aux scripts précédents) :
#   src/                     <- ce script
#   data/processed/          <- price_range_output.csv, ms_garch_fan_chart_inputs.csv,
#                                ms_garch_regime_conditional_forecast.csv
#   graphs/Price_range_plot/ <- PNG produits ici
#
# NOTE : ms_garch_fan_chart_inputs.csv ne contient que 4 niveaux de confiance
# (20/50/80/95%), pas 7 comme l'indique la légende du fichier en section 9 du
# document — reliquat de la proposition initiale à 7 niveaux, revue à 4.
# Corrige cette légende dans Price_Range.md. Le graph 1 ci-dessous lit le
# nombre de niveaux directement depuis le CSV (dynamique, pas codé en dur),
# donc il s'adapte automatiquement si tu corriges ça côté R plus tard.
#
# Toutes les largeurs de bande ont été revérifiées indépendamment (recalcul
# Python depuis les CSV) et correspondent exactement au tableau de la
# section 8 du document.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Price_range_plot")
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
range_out <- read_csv(file.path(processed_dir, "price_range_output.csv"),
                      col_types = cols(date = col_date(), last_price = col_double(),
                                       confidence_level = col_double(), p_min = col_double(),
                                       p_max = col_double(), range_width_pct = col_double()))

fan_inputs <- read_csv(file.path(processed_dir, "ms_garch_fan_chart_inputs.csv"),
                       col_types = cols(confidence_level = col_double(), alpha_low = col_double(),
                                        alpha_high = col_double(), return_q_low = col_double(),
                                        return_q_high = col_double(), last_date = col_date(),
                                        last_price = col_double()))

regime_cond <- read_csv(file.path(processed_dir, "ms_garch_regime_conditional_forecast.csv"),
                        col_types = cols(confidence_level = col_double(), regime = col_character(),
                                         return_q_low = col_double(), return_q_high = col_double(),
                                         last_date = col_date(), last_price = col_double()))

last_price <- fan_inputs$last_price[1]

# Convertit un rendement log (%) en prix
ret_to_price <- function(ret_pct, price = last_price) price * exp(ret_pct / 100)

# ==============================================================================
# GRAPH 1 — Fan chart : bandes nichées, 3 panneaux (mixture / calme / stress)
# ==============================================================================
mixture_panel <- fan_inputs %>%
  transmute(panel = "Opérationnel (mixture)", confidence_level,
            p_min = ret_to_price(return_q_low), p_max = ret_to_price(return_q_high))

regime_panel <- regime_cond %>%
  mutate(panel = recode(regime, "1_calm" = "Régime calme (certain)",
                        "2_stress" = "Régime de stress (certain)")) %>%
  transmute(panel, confidence_level,
            p_min = ret_to_price(return_q_low), p_max = ret_to_price(return_q_high))

fan_all <- bind_rows(mixture_panel, regime_panel) %>%
  mutate(panel = factor(panel, levels = c("Régime calme (certain)", "Opérationnel (mixture)",
                                          "Régime de stress (certain)")),
         confidence_level = factor(confidence_level,
                                   levels = sort(unique(confidence_level), decreasing = TRUE)))

g1 <- ggplot(fan_all, aes(x = panel)) +
  geom_rect(aes(xmin = as.numeric(panel) - 0.35, xmax = as.numeric(panel) + 0.35,
                ymin = p_min, ymax = p_max, fill = confidence_level),
            alpha = 0.55) +
  geom_hline(yintercept = last_price, linetype = "dashed", color = "grey20", linewidth = 0.5) +
  scale_fill_brewer(palette = "Blues", direction = -1,
                    labels = function(x) scales::percent(as.numeric(x))) +
  labs(title = "Fan chart — bandes de confiance nichées par panneau",
       subtitle = str_wrap(paste0("EUR/USD = ", last_price, " (2026-09-11) — bandes 20/50/80/95% nichées"), width = 65),
       x = NULL, y = "EUR/USD", fill = "Niveau de\nconfiance")

save_fig(g1, "01_fan_chart_three_panels.png", width = 8.5, height = 5)

# ==============================================================================
# GRAPH 2 — Comparaison ex-post : OHLC réel du 2026-09-14 vs plage prévue à 95%
# ==============================================================================
range95 <- range_out %>% filter(confidence_level == 0.95)

ohlc_df <- tibble(
  label = c("Open", "High", "Low", "Close"),
  valeur = c(1.1597, 1.1601, 1.1523, 1.1549)
)

g2 <- ggplot() +
  geom_rect(aes(xmin = 0.5, xmax = 1.5, ymin = range95$p_min, ymax = range95$p_max),
            fill = "steelblue3", alpha = 0.3) +
  geom_hline(yintercept = range95$p_min, linetype = "dashed", color = "steelblue4") +
  geom_hline(yintercept = range95$p_max, linetype = "dashed", color = "steelblue4") +
  geom_point(data = ohlc_df, aes(x = 1, y = valeur, shape = label, color = label), size = 4) +
  geom_text(data = ohlc_df, aes(x = 1.15, y = valeur, label = label), size = 3.5, hjust = 0) +
  scale_x_continuous(limits = c(0.3, 1.8), breaks = NULL) +
  labs(title = "Plage prévue (95%) vs. OHLC réel — 2026-09-14",
       subtitle = str_wrap("Open, High, Close dans la plage — Low sous la borne basse de ~10 pips (voir §7.2 du document)", width = 65),
       x = NULL, y = "EUR/USD", color = NULL, shape = NULL) +
  theme(legend.position = "none")

save_fig(g2, "02_expost_ohlc_vs_range.png")

# ==============================================================================
# GRAPH 3 — Plage 95% : mixture vs calme vs stress (dumbbell)
# ==============================================================================
range95_regime <- regime_cond %>%
  filter(confidence_level == 0.95) %>%
  transmute(scenario = recode(regime, "1_calm" = "Régime calme (certain)",
                              "2_stress" = "Régime de stress (certain)"),
            p_min = ret_to_price(return_q_low), p_max = ret_to_price(return_q_high))

range95_mix <- tibble(scenario = "Opérationnel (mixture)", p_min = range95$p_min, p_max = range95$p_max)

range95_all <- bind_rows(range95_mix, range95_regime) %>%
  mutate(scenario = factor(scenario, levels = c("Régime de stress (certain)", "Opérationnel (mixture)",
                                                "Régime calme (certain)")))

g3 <- ggplot(range95_all, aes(y = scenario)) +
  geom_vline(xintercept = last_price, linetype = "dashed", color = "grey40") +
  geom_segment(aes(x = p_min, xend = p_max, yend = scenario), linewidth = 3, color = "steelblue3", alpha = 0.6) +
  geom_point(aes(x = p_min), size = 3, color = "steelblue4") +
  geom_point(aes(x = p_max), size = 3, color = "firebrick") +
  labs(title = "Plage à 95% selon le scénario de régime",
       subtitle = str_wrap("Ligne pointillée = prix actuel (1.1604) — la plage stress est ~1.88x plus large", width = 65),
       x = "EUR/USD", y = NULL)

save_fig(g3, "03_range95_by_scenario.png")

# ==============================================================================
# GRAPH 4 — Ratio stress/calme selon le niveau de confiance
#           (compression à 95% — la trouvaille la plus fine du document, §8)
# ==============================================================================
ratio_df <- tibble(
  confidence_level = c(0.20, 0.50, 0.80, 0.95),
  ratio = c(2.09, 2.07, 2.00, 1.88)
)

g4 <- ggplot(ratio_df, aes(x = factor(confidence_level), y = ratio)) +
  geom_col(fill = "firebrick", width = 0.5, alpha = 0.85) +
  geom_text(aes(label = paste0(ratio, "x")), vjust = -0.5, size = 4) +
  geom_hline(yintercept = 2, linetype = "dotted", color = "grey40") +
  scale_x_discrete(labels = function(x) scales::percent(as.numeric(x))) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Ratio largeur stress / calme, selon le niveau de confiance",
       subtitle = str_wrap("Le ratio ne monte pas à 95% — il redescend : queue de la distribution Student-t du régime calme (\u03bd1\u22487) qui gonfle disproportionnellement", width = 65),
       x = "Niveau de confiance", y = "Ratio (largeur stress / largeur calme)")

save_fig(g4, "04_stress_calm_ratio_by_level.png")

# ==============================================================================
# GRAPH 5 — Impact économique : conversion de 1M€ selon le régime
# ==============================================================================
econ_df <- tibble(
  scenario = factor(c("Calme (certain)", "Stress (certain)"), levels = c("Calme (certain)", "Stress (certain)")),
  spread_usd = c(14100, 26500)
)

g5 <- ggplot(econ_df, aes(x = scenario, y = spread_usd, fill = scenario)) +
  geom_col(width = 0.55) +
  geom_text(aes(label = paste0("$", scales::comma(spread_usd))), vjust = -0.5, size = 4) +
  scale_fill_manual(values = c("Calme (certain)" = "steelblue3", "Stress (certain)" = "firebrick")) +
  scale_y_continuous(labels = scales::dollar, expand = expansion(mult = c(0, 0.22))) +
  labs(title = "Impact économique — conversion de EUR 1 000 000",
       subtitle = str_wrap("Écart entre bornes haute et basse de la plage à 95%, selon le régime", width = 65),
       x = NULL, y = "Écart (USD)") +
  theme(legend.position = "none")

save_fig(g5, "05_economic_impact_eur1m.png")

# ==============================================================================
cat("Terminé —", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")