"""
data_loader_fred.py
Downloads USD/EUR daily exchange rate data directly from FRED
(Federal Reserve Economic Data), as a stable alternative to yfinance
for FX tickers.

Series used: DEXUSEU (U.S. Dollars to Euro Spot Exchange Rate)
Note: FRED's DEXUSEU is USD per EUR (same convention as EUR/USD quoted
as "how many dollars per euro" — double-check against your definition
of P(t) from earlier in the project; if you need the inverse, use
1 / rate).
"""

import pandas as pd


def load_eurusd_fred(start="2010-01-01", end=None, save_path=None):
    """
    Download DEXUSEU (USD/EUR) daily data directly from FRED's CSV endpoint.

    Parameters
    ----------
    start : str
        Start date, format 'YYYY-MM-DD'.
    end : str or None
        End date. If None, uses today's date.
    save_path : str or None
        If provided, saves the cleaned data as CSV at this path.

    Returns
    -------
    pd.DataFrame
        DataFrame with a DatetimeIndex and a 'Close' column
        (named 'Close' for compatibility with the rest of the pipeline).
    """
    if end is None:
        end = pd.Timestamp.today().strftime("%Y-%m-%d")

    url = (
        "https://fred.stlouisfed.org/graph/fredgraph.csv"
        f"?id=DEXUSEU&cosd={start}&coed={end}"
    )

    data = pd.read_csv(url, parse_dates=["observation_date"])
    data = data.rename(columns={"observation_date": "Date", "DEXUSEU": "Close"})
    data = data.set_index("Date")

    # FRED marks missing observations (holidays) as "." — drop them
    data["Close"] = pd.to_numeric(data["Close"], errors="coerce")
    data = data.dropna()

    if data.empty:
        raise ValueError("No data returned from FRED — check date range or connectivity.")

    if save_path:
        data.to_csv(save_path)
        print(f"Raw data saved to {save_path}")

    return data


if __name__ == "__main__":
    df = load_eurusd_fred(start="2010-01-01", save_path="../data/raw/eurusd_daily.csv")
    print(df.tail())
    print(f"\nTotal observations: {len(df)}")