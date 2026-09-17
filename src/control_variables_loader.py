"""
control_variables_loader.py
Downloads the three control variable series from FRED, all daily,
all via the same stable CSV endpoint already used for EUR/USD
(see data_loader_fred.py).

Series:
    DFF       - Federal Funds Effective Rate (daily)
    ECBDFR    - ECB Deposit Facility Rate for Euro Area (daily)
    DTWEXBGS  - Nominal Broad U.S. Dollar Index (daily, base Jan 2006=100)

Note on DTWEXBGS as a DXY proxy: this is NOT the commercial DXY index.
DXY weights a basket of 6 currencies dominated by the euro (~58%
weight), while DTWEXBGS is a broad trade-weighted index including
emerging-market currencies. Both measure "dollar strength" but are not
interchangeable. Documented as a limitation in methodology.md.
"""

import pandas as pd


def load_fred_series(series_id, col_name, start="2010-01-01", end=None, save_path=None):
    """
    Generic loader for any FRED series via its public CSV endpoint.

    Parameters
    ----------
    series_id : str
        FRED series ID (e.g. 'DFF', 'ECBDFR', 'DTWEXBGS').
    col_name : str
        Name to give the resulting value column.
    start : str
        Start date, format 'YYYY-MM-DD'.
    end : str or None
        End date. If None, uses today's date.
    save_path : str or None
        If provided, saves the cleaned data as CSV at this path.

    Returns
    -------
    pd.DataFrame
        DataFrame with a DatetimeIndex ('Date') and one value column.
    """
    if end is None:
        end = pd.Timestamp.today().strftime("%Y-%m-%d")

    url = (
        "https://fred.stlouisfed.org/graph/fredgraph.csv"
        f"?id={series_id}&cosd={start}&coed={end}"
    )

    data = pd.read_csv(url, parse_dates=["observation_date"])
    data = data.rename(columns={"observation_date": "Date", series_id: col_name})
    data = data.set_index("Date")

    # FRED marks missing observations (holidays, etc.) as "." — drop them
    data[col_name] = pd.to_numeric(data[col_name], errors="coerce")
    data = data.dropna()

    if data.empty:
        raise ValueError(f"No data returned for {series_id} — check date range or connectivity.")

    if save_path:
        data.to_csv(save_path)
        print(f"{series_id} saved to {save_path}")

    return data


def load_all_controls(start="2010-01-01", end=None, save_dir="../data/raw"):
    """
    Load all three control series and return them as a single merged
    DataFrame, aligned by date (inner join — only dates present in all
    three series are kept; rate series update far less often than they
    have daily observations, but calendar coverage may still differ
    slightly across sources).

    Returns
    -------
    pd.DataFrame
        Columns: fed_rate, ecb_rate, dxy_proxy
    """
    fed = load_fred_series("DFF", "fed_rate", start, end,
                            save_path=f"{save_dir}/fed_rate.csv")
    ecb = load_fred_series("ECBDFR", "ecb_rate", start, end,
                            save_path=f"{save_dir}/ecb_rate.csv")
    dxy = load_fred_series("DTWEXBGS", "dxy_proxy", start, end,
                            save_path=f"{save_dir}/dxy_proxy.csv")

    merged = fed.join(ecb, how="inner").join(dxy, how="inner")
    return merged


if __name__ == "__main__":
    controls = load_all_controls(start="2010-01-01",
                                  save_dir="../data/raw")
    print(controls.tail())
    print(f"\nTotal aligned observations: {len(controls)}")
    controls.to_csv("../data/processed/control_variables.csv")
