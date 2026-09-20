# ==============================================================================
# Graphs — Garch_Stability.md
# Génère les 2 figures retenues pour le document Garch_Stability.md
# Sortie : PNG, 300 dpi, dans graphs/Garch_Stability_plot/
#
# Entrée :
#   data/processed/garch_stability_comparison.csv
#     period, start_date, end_date, n_obs, omega, alpha, beta, nu,
#     alpha_plus_beta, half_life_days, log_likelihood, aic
#
# Mapping figure -> section du document :
#   01  §3      paramètres omega, alpha, beta, nu par sous-période
#   02  §4, §5  demi-vie en fonction de alpha+beta (le mécanisme de l'anomalie P2
#               et de l'écart P3 / P1-P4-P5)
#
# Non générés (volontairement) : le tableau §5 (déjà lisible), les p-values de
# la période 2 (dans le texte, absentes du CSV).
#
# LIMITE À CONNAÎTRE : le CSV ne contient aucune erreur-type par période. Les
# figures montrent donc des estimations ponctuelles sans intervalle. Le bloc
# "Informatif" de la console compare le modèle unique au modèle en 5 périodes
# avec les vraisemblances du CSV et les valeurs publiées dans GARCH_1_1.md.
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ---- 0. Chemins ---------------------------------------------------------
processed_dir <- here("data", "processed")
output_dir    <- here("graphs", "Garch_Stability_plot")
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

col_pt  <- "steelblue4"
col_bad <- "firebrick"    # période 2 : demi-vie non interprétable (doc §4)

# ---- 1. Chargement -------------------------------------------------------
stab <- read_csv(file.path(processed_dir, "garch_stability_comparison.csv"),
                 col_types = cols(period = col_character(),
                                  start_date = col_date(), end_date = col_date(),
                                  n_obs = col_integer(), omega = col_double(),
                                  alpha = col_double(), beta = col_double(),
                                  nu = col_double(), alpha_plus_beta = col_double(),
                                  half_life_days = col_double(),
                                  log_likelihood = col_double(), aic = col_double())) %>%
  arrange(start_date) %>%
  mutate(p = row_number(),
         period_lab = paste0("P", p, "\n", format(start_date, "%Y"), "\u2013", format(end_date, "%y")),
         delta = 1 - alpha_plus_beta)

# ---- 2. CONTRÔLE (s'imprime dans la console R) ---------------------------
check <- function(label, got, doc, tol) {
  ok <- all(abs(got - doc) <= tol)
  cat(sprintf("%-40s obtenu: %-42s doc: %-42s [%s]\n", label,
              paste(round(got, 6), collapse = " / "),
              paste(doc, collapse = " / "),
              if (ok) "OK" else "ÉCART"))
  ok
}

cat("\n================ CONTRÔLE GARCH_STABILITY ================\n")
res <- c(
  check("n_obs par période", stab$n_obs, rep(835, 5), 0),
  check("Total des observations", sum(stab$n_obs), 4175, 0),
  check("Périodes contiguës (jours de trou)",
        as.numeric(stab$start_date[-1] - stab$end_date[-5]) > 0, rep(1, 4), 0),
  check("omega, doc §3", stab$omega, c(0.004378, 0.000382, 0.000233, 0.003341, 0.001878), 6e-7),
  check("alpha, doc §3", stab$alpha, c(0.0283, 0.0386, 0.0170, 0.0720, 0.0408), 6e-5),
  check("beta, doc §3", stab$beta, c(0.9612, 0.9614, 0.9809, 0.9192, 0.9494), 6e-5),
  check("nu, doc §3", stab$nu, c(12.59, 5.95, 10.58, 6.89, 5.54), 6e-3),
  check("alpha+beta, doc §3", stab$alpha_plus_beta,
        c(0.9895, 0.999991, 0.9979, 0.9912, 0.9902), 6e-5),
  check("Demi-vie (jours), doc §3", stab$half_life_days,
        c(65.5, 80366, 335.1, 78.5, 70.5), c(0.06, 0.6, 0.06, 0.06, 0.06)),
  check("Demi-vie = ln(0,5)/ln(alpha+beta)", log(0.5) / log(stab$alpha_plus_beta),
        stab$half_life_days, 1e-6 * stab$half_life_days),
  check("Paramètres estimés par période (AIC, LL)", (stab$aic + 2 * stab$log_likelihood) / 2,
        rep(5, 5), 1e-6)
)

cat("\n-- Informatif --\n")
cat("Volatilité de long terme sqrt(omega / (1 - alpha - beta)), % par jour :",
    round(sqrt(stab$omega / stab$delta), 3), "\n")
cat("  -> période 2 :", round(sqrt(stab$omega[2] / stab$delta[2]), 2),
    "% par jour : valeur absurde pour l'EUR/USD (voir §4 du document)\n")
cat(sprintf("Écart de alpha+beta entre P3 et P4 : %.4f (demi-vie %.0f -> %.0f jours)\n",
            stab$alpha_plus_beta[3] - stab$alpha_plus_beta[4],
            stab$half_life_days[3], stab$half_life_days[4]))

# Modèle unique (valeurs publiées dans GARCH_1_1.md) contre modèle en 5 périodes
LL0 <- -2818.39; AIC0 <- 5646.78; BIC0 <- 5678.46; n_tot <- 4175; k0 <- 5; k1 <- 25
LL1 <- sum(stab$log_likelihood); AIC1 <- sum(stab$aic); BIC1 <- k1 * log(n_tot) - 2 * LL1
LR  <- 2 * (LL1 - LL0); df <- k1 - k0
cat(sprintf("Test du rapport de vraisemblance, paramètres identiques sur les 5 périodes : LR = %.2f, ddl = %d, p = %.3f (seuil 5 %% : %.2f)\n",
            LR, df, pchisq(LR, df, lower.tail = FALSE), qchisq(0.95, df)))
cat(sprintf("AIC : modèle unique %.2f, 5 périodes %.2f (écart %+.2f) ; BIC : %.2f contre %.2f (écart %+.2f)\n",
            AIC0, AIC1, AIC1 - AIC0, BIC0, BIC1, BIC1 - BIC0))
cat("  (approximatif : chaque période réinitialise la récursion de variance ; cela avantage\n",
    "   légèrement le modèle à 5 périodes, donc le sens du biais ne favorise pas la conclusion.)\n", sep = "")
cat(if (all(res)) "\n=> Tous les contrôles du document sont OK.\n" else
      "\n=> ATTENTION : au moins un écart. Vérifier avant d'utiliser les figures.\n")
cat("==========================================================\n\n")

# ==============================================================================
# FIGURE 01 — Paramètres par sous-période (§3)
# ==============================================================================
par_long <- stab %>%
  select(p, period_lab, omega, alpha, beta, nu) %>%
  pivot_longer(c(omega, alpha, beta, nu), names_to = "param", values_to = "value") %>%
  mutate(param = factor(param, levels = c("omega", "alpha", "beta", "nu"),
                        labels = c("\u03c9", "\u03b1", "\u03b2", "\u03bd")),
         period_lab = factor(period_lab, levels = stab$period_lab),
         weak = (param == "\u03c9" & p == 2))          # omega non significatif en P2 (doc §4)

lab_weak <- par_long %>% filter(weak) %>%
  mutate(label = "non significatif\n(p = 0,519, doc §4)")

g1 <- ggplot(par_long, aes(x = period_lab, y = value, group = param)) +
  geom_line(color = "grey65", linewidth = 0.4) +
  geom_point(aes(fill = ifelse(weak, "white", col_pt)), shape = 21, color = col_pt,
             size = 3, stroke = 1) +
  geom_text(data = lab_weak, aes(label = label), vjust = -0.6, size = 2.8, color = "grey25",
            lineheight = 0.9) +
  facet_wrap(~param, scales = "free_y", nrow = 2) +
  scale_fill_identity() +
  scale_y_continuous(expand = expansion(mult = c(0.08, 0.22))) +
  labs(title = "GARCH(1,1) Student-t : paramètres par sous-période",
       subtitle = "835 observations par période. Estimations ponctuelles ; marqueur creux : \u03c9 non significatif en période 2",
       caption = "Les erreurs-types par période ne figurent pas dans le CSV exporté : aucun intervalle n'est tracé.",
       x = NULL, y = NULL) +
  theme(plot.title.position = "plot", plot.caption.position = "plot",
        plot.subtitle = element_text(size = 9.5),
        plot.caption = element_text(size = 7.5, hjust = 0, color = "grey30"),
        strip.text = element_text(face = "bold", size = 12),
        axis.text.x = element_text(size = 8.5))

save_fig(g1, "01_parameters_by_period.png", width = 8, height = 6)

# ==============================================================================
# FIGURE 02 — Demi-vie en fonction de alpha+beta (§4, §5)
#   Abscisse : -log10(1 - (alpha+beta)), donc plus à droite = plus proche de la
#   frontière IGARCH (alpha+beta = 1). Courbe exacte : ln(0,5) / ln(alpha+beta).
#   Ordonnée en échelle log.
# ==============================================================================
curve_df <- tibble(x = seq(1.6, 5.4, length.out = 600)) %>%
  mutate(hl = log(0.5) / log(1 - 10^(-x)))

fmt_hl <- function(y) ifelse(y < 1000, gsub("\\.", ",", sprintf("%.1f", y)),
                             formatC(round(y), format = "d", big.mark = " "))

# Positions manuelles des étiquettes (dx en unités d'abscisse, fy multiplicatif en y)
place <- tibble(p  = 1:5,
                dx = c(0.05, -0.08, 0.06, 0.05, 0.05),
                fy = c(0.50, 1.00, 0.80, 0.92, 0.68),
                hj = c(0, 1, 0, 0, 0))
pts <- stab %>%
  left_join(place, by = "p") %>%
  mutate(x = -log10(delta), y = half_life_days,
         lab = paste0("P", p, " : ", fmt_hl(y), " j"),
         bad = p == 2)

g2 <- ggplot(curve_df, aes(x = x, y = hl)) +
  geom_line(color = "grey40", linewidth = 0.7) +
  geom_point(data = pts, aes(x = x, y = y, color = bad), size = 3.2, inherit.aes = FALSE) +
  geom_text(data = pts, aes(x = x + dx, y = y * fy, label = lab, hjust = hj, color = bad),
            size = 3.2, show.legend = FALSE, inherit.aes = FALSE) +
  scale_color_manual(values = c(`FALSE` = col_pt, `TRUE` = col_bad), guide = "none") +
  scale_x_continuous(breaks = 2:5, labels = c("0,99", "0,999", "0,9999", "0,99999"),
                     limits = c(1.6, 5.4)) +
  scale_y_log10(breaks = c(30, 100, 300, 1000, 10000, 100000),
                labels = label_number(big.mark = " ", accuracy = 1)) +
  labs(title = "Demi-vie du choc en fonction de la persistance \u03b1+\u03b2",
       subtitle = paste0("Entre P3 et P4, \u03b1+\u03b2 ne diffère que de ",
                         number(stab$alpha_plus_beta[3] - stab$alpha_plus_beta[4], accuracy = 0.0001, decimal.mark = ","),
                         ", mais la demi-vie passe de ",
                         number(stab$half_life_days[3], accuracy = 1), " à ",
                         number(stab$half_life_days[4], accuracy = 1), " jours"),
       caption = paste0("Courbe exacte ln(0,5) / ln(\u03b1+\u03b2), axe des abscisses gradué en nombre de « 9 » (plus à droite = plus proche de 1).\n",
                        "Points : estimations ponctuelles par période, sans intervalle (erreurs-types absentes du CSV)."),
       x = "\u03b1 + \u03b2", y = "Demi-vie (jours, échelle log)") +
  theme(plot.title.position = "plot", plot.caption.position = "plot",
        plot.subtitle = element_text(size = 9.5),
        plot.caption = element_text(size = 7.5, hjust = 0, color = "grey30"))

save_fig(g2, "02_halflife_vs_persistence.png", width = 8, height = 4.8)

# ==============================================================================
cat("Terminé \u2014", length(list.files(output_dir, pattern = "\\.png$")),
    "graphs générés dans", output_dir, "\n")
