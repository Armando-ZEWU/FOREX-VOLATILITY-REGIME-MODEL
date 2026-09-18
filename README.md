# FX Volatility Regime Model

> A quantitative model exploring the FX market (EUR/USD) to measure a "fear"/volatility proxy that explains returns and detects market regimes (low/mean/high).

**Status: ongoing research project — undergraduate student in International Economics.**
This is not a production trading tool. It's an applied econometrics research exercise, meant to be honest about its limitations rather than impressive on paper.

## Why this project

I first encountered risk aversion in microeconomics — a stable individual preference in expected utility theory. But financial markets clearly don't behave as if risk perception were constant: volatility spikes, sentiment shifts, and markets swing between calm and panic. This raised a question that microeconomic theory alone doesn't fully answer: can this *time-varying* market-wide risk perception — closer to behavioral finance than to classical risk aversion — be measured quantitatively on the FX market, the most liquid market in the world? And if so, can it help explain returns and produce a usable price range rather than a purely qualitative narrative?

This project is also a way to apply what I'm building in Econometrics and Statistical Decision-Making during my International Economics degree at FASEG, University of Lomé — and it connects naturally to my coursework in International Trade and International Monetary Economics, since FX markets sit at the intersection of both.

## Research question

Can a time-varying, market-wide risk perception on the foreign exchange market be measured quantitatively and tested statistically — rather than only described qualitatively — and used to help explain returns and detect market regimes in real time?

**What this model does NOT claim to do**: predict future price direction with certainty. The goal is to support decision-making, not guarantee an outcome — see the Limitations section.

## Methodology (summary)

1. Modeling EUR/USD log returns (not raw prices, to avoid non-stationarity issues)
2. Building a proprietary FX volatility/fear proxy, since access to proprietary indices (CVIX, JPMorgan VXY) is not available
3. Calibrating a GARCH(1,1) model to isolate the volatility shock from its mechanical inertia (clustering)
4. [To be completed as the project progresses: regression specification, regime detection via HMM / Markov-switching]

The full reasoning, including discarded options and why, is documented in [`docs/methodology.md`](docs/methodology.md).

## Repo structure

```
fx-vol-regime-model/
├── data/
│   ├── raw/              # raw downloaded data, never modified
│   └── processed/        # log returns, cleaned series
├── src/
│   ├── data_loader.py    # data download/cleaning
│   ├── features.py       # returns computation, volatility variable transformations
│   ├── garch_model.py    # GARCH calibration, shock extraction
│   └── regression.py     # econometric specification r(t+1) = ...
├── docs/
│   └── methodology.md    # detailed methodological log (decisions, corrections, reasoning)
├── requirements.txt
└── README.md
```

## Data sources

- [Yahoo Finance](https://finance.yahoo.com) (`EURUSD=X`, via `yfinance`) — daily closing prices
- [FRED](https://fred.stlouisfed.org) (DEXUSEU series) — for pairing with US macro data
- [ECB Statistical Data Warehouse](https://data.ecb.europa.eu) — official reference rates

## Known and acknowledged limitations

- The volatility proxy used is a **realized/conditional volatility** (GARCH), not an **implied volatility** — it does not capture market expectations, unlike an index such as the CVIX (inaccessible without Bloomberg/Refinitiv access)
- The causal link between volatility and future returns still needs rigorous testing (simultaneity risk)
- The model is calibrated on daily data only, due to lack of access to quality intraday data

## Reproduce

```bash
git clone [url]
cd fx-vol-regime-model
pip install -r requirements.txt
```

[Run instructions to be completed once the scripts are written]

## Author

[ZEWU Yawo Armand Isaac / Armando-ZEWU] — Undergraduate student in International Economics, FASEG, University of Lomé.

