"""
abm_analysis.py
================
Reusable post-processing module for RABM / b7ABM MATLAB simulation outputs.

Consolidates the shared logic from:
  - Ash22_png.ipynb        (time-series plots, % change vs baseline, CIs)
  - Ash22_choropleths.ipynb (SA -> neighborhood aggregation, final-level maps)
  - New_EQ_07sep.ipynb      (derived variables, safe helpers, PDF export)

Typical usage
-------------
    from abm_analysis import (
        Config, load_runs, add_derived_variables,
        pct_change_vs_baseline, paired_pct_change,
        mean_ci, plot_timeseries, plot_all_timeseries,
    )

    cfg = Config(
        mat_dir=r"D:\\MATLAB\\Ash\\rocketFinal",
        scenarios={
            "Ash22Q 0":   "baseline",
            "Ash22Q 395": "395 hits base",
        },
        n_runs=30,
        day_slice=slice(90, None),
    )

    data = load_runs(cfg)
    data = add_derived_variables(data, cfg)
    pct  = pct_change_vs_baseline(data, baseline="baseline")
    plot_all_timeseries(pct, cfg, out_dir="plots", relative=True)
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Callable, Iterable, Optional, Sequence

import numpy as np
import pandas as pd
import scipy.io
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.lines import Line2D

# ---------------------------------------------------------------------------
# 1. Variable metadata
# ---------------------------------------------------------------------------

#: Default variable set. (main title, y-axis label).
#: Titles starting with "Mean" are averaged across SAs; all others are summed.
VARIABLE_TITLES: dict[str, tuple[str, str]] = {
    "SA_OUTCOME":  ("Mean Workplace Outcome",           "Outcome"),
    "SA_POP":      ("Total Population",                 "Population"),
    "SA_PRICE":    ("Mean Asset Price per Meter",       "Price (per m2)"),
    "SA_SERVICE":  ("Total Service Count",              "Service Count"),
    "SA_WAGE":     ("Mean Wage",                        "Wage"),
    "SA_WP":       ("Workplace Count",                  "Workplace Count"),
    "SA_RESIDENT": ("Total Residential Count",          "Residential Count"),
    "SA_HOUSE":    ("Mean Residential Price per Meter", "Residential Price (per m2)"),
    "SA_AREA":     ("Total Commercial Floorspace",      "Floorspace"),
    "SA_JOBS":     ("Mean Share of Occupied Jobs",      "Occupied Jobs"),
    "SA_IDLE":     ("Mean Unemployment Rate",           "Unemployment Rate"),
    "SA_COMMUTE":  ("Mean Outbound Commuting Rate",     "Commuting Rate"),
    "SA_FIRST":    ("Households in 1st Percentile",     "HH in 1st Decile"),
    "SA_SECOND":   ("Households in 2nd Percentile",     "HH in 2nd Decile"),
    "SA_THIRD":    ("Households in 3rd Percentile",     "HH in 3rd Decile"),
    "SA_FOURTH":   ("Households in 4th Percentile",     "HH in 4th Decile"),
    "SA_FIFTH":    ("Households in 5th Percentile",     "HH in 5th Decile"),
    "SA_SIXTH":    ("Households in 6th Percentile",     "HH in 6th Decile"),
    "SA_SEVENTH":  ("Households in 7th Percentile",     "HH in 7th Decile"),
    "SA_EIGHTH":   ("Households in 8th Percentile",     "HH in 8th Decile"),
    "SA_NINTH":    ("Households in 9th Percentile",     "HH in 9th Decile"),
    "SA_TENTH":    ("Households in 10th Percentile",    "HH in 10th Decile"),
    # Derived (created by add_derived_variables):
    "SA_JPM2":        ("Jobs per m2",                 "Jobs/m2"),
    "SA_JPP":         ("Jobs per Occupied Asset",     "Jobs per HH"),
    "SA_TOTAL_HH":    ("Total Households",            "Households"),
    "SA_JPTOTAL":     ("Jobs per Total Households",   "Jobs per Household"),
    "SA_WAGE_TOT":    ("Total Wage Income",           "Total Wages"),
    "SA_WAGE_HPRICE": ("Wage-to-House Price Ratio",   "Wage/Price"),
}

DECILES: list[str] = [
    "SA_FIRST", "SA_SECOND", "SA_THIRD", "SA_FOURTH", "SA_FIFTH",
    "SA_SIXTH", "SA_SEVENTH", "SA_EIGHTH", "SA_NINTH", "SA_TENTH",
]


def is_mean_variable(var: str, titles: dict | None = None) -> bool:
    """True if this variable is aggregated across SAs by mean (else sum)."""
    titles = titles or VARIABLE_TITLES
    main_title = titles.get(var, (var, var))[0]
    return main_title.lower().startswith("mean")


# ---------------------------------------------------------------------------
# 2. Configuration
# ---------------------------------------------------------------------------

@dataclass
class Config:
    """Everything that varies between analyses lives here."""

    mat_dir: str
    #: file-prefix -> scenario label, e.g. {"Ash22Q 0": "baseline"}
    scenarios: dict[str, str] = field(default_factory=dict)
    n_runs: int = 30
    #: which day-columns to keep, e.g. slice(90, None) or slice(35, 760)
    day_slice: slice = slice(90, None)
    variables: list[str] = field(
        default_factory=lambda: [v for v in VARIABLE_TITLES if not v.startswith(("SA_JP", "SA_TOTAL", "SA_WAGE_"))]
    )
    variable_titles: dict[str, tuple[str, str]] = field(
        default_factory=lambda: dict(VARIABLE_TITLES)
    )
    #: scenario label -> matplotlib color
    colors: dict[str, str] = field(default_factory=dict)
    #: scenario label -> dash tuple, e.g. (2, 2). Empty tuple = solid.
    dashes: dict[str, tuple] = field(default_factory=dict)
    verbose: bool = True

    def mat_path(self, prefix: str, run: int) -> str:
        return os.path.join(self.mat_dir, f"{prefix} {run}.mat")


# ---------------------------------------------------------------------------
# 3. Loading
# ---------------------------------------------------------------------------

def load_runs(cfg: Config, aggregate: bool = True) -> dict:
    """Load .mat files for all scenarios/runs.

    Returns
    -------
    dict
        data[var][scenario_label] = list of per-run pd.Series (day-indexed)
        if aggregate=True, else list of per-run DataFrames (SA x day).
    """
    data: dict[str, dict[str, list]] = {v: {} for v in cfg.variables}

    for prefix, scen in cfg.scenarios.items():
        for run in range(1, cfg.n_runs + 1):
            path = cfg.mat_path(prefix, run)
            try:
                mat = scipy.io.loadmat(path, variable_names=cfg.variables)
            except Exception as e:  # noqa: BLE001
                if cfg.verbose:
                    print(f"[warn] could not load {path}: {e}")
                continue

            for v in cfg.variables:
                if v not in mat:
                    continue
                df = pd.DataFrame(mat[v]).iloc[:, cfg.day_slice]
                if aggregate:
                    series = df.mean(axis=0) if is_mean_variable(v, cfg.variable_titles) else df.sum(axis=0)
                    data[v].setdefault(scen, []).append(series)
                else:
                    data[v].setdefault(scen, []).append(df)
    return data


# ---------------------------------------------------------------------------
# 4. Derived variables
# ---------------------------------------------------------------------------

def safe_ratio(num: pd.Series, den: pd.Series) -> pd.Series:
    return num.div(den).replace([np.inf, -np.inf], np.nan).fillna(0)


def _pair_runs(a: Sequence, b: Sequence) -> Iterable[tuple]:
    for i in range(min(len(a), len(b))):
        yield a[i], b[i]


def add_derived_variables(data: dict, cfg: Config) -> dict:
    """Compute the standard derived variables in-place (and return data).

    SA_JPM2        = SA_WP / SA_AREA          (jobs per m2)
    SA_JPP         = SA_WP / SA_POP           (jobs per person)
    SA_TOTAL_HH    = sum of decile counts     (total households)
    SA_JPTOTAL     = SA_WP / SA_TOTAL_HH      (jobs per household)
    SA_WAGE_TOT    = SA_WAGE * SA_TOTAL_HH    (total wage bill)
    SA_WAGE_HPRICE = SA_WAGE / SA_HOUSE       (affordability ratio)
    """
    scens = list(cfg.scenarios.values())

    def ratio_var(name: str, num: str, den: str) -> None:
        data[name] = {s: [] for s in scens}
        for s in scens:
            for a, b in _pair_runs(data.get(num, {}).get(s, []),
                                   data.get(den, {}).get(s, [])):
                data[name][s].append(safe_ratio(a, b))

    ratio_var("SA_JPM2", "SA_WP", "SA_AREA")
    ratio_var("SA_JPP", "SA_WP", "SA_POP")

    data["SA_TOTAL_HH"] = {s: [] for s in scens}
    for s in scens:
        dec_lists = [data[d][s] for d in DECILES if d in data and s in data[d]]
        if not dec_lists or any(len(lst) == 0 for lst in dec_lists):
            continue
        m = min(len(lst) for lst in dec_lists)
        for i in range(m):
            data["SA_TOTAL_HH"][s].append(sum(lst[i] for lst in dec_lists))

    ratio_var("SA_JPTOTAL", "SA_WP", "SA_TOTAL_HH")

    data["SA_WAGE_TOT"] = {s: [] for s in scens}
    for s in scens:
        for wage, hh in _pair_runs(data.get("SA_WAGE", {}).get(s, []),
                                   data.get("SA_TOTAL_HH", {}).get(s, [])):
            data["SA_WAGE_TOT"][s].append(wage.mul(hh).fillna(0))

    ratio_var("SA_WAGE_HPRICE", "SA_WAGE", "SA_HOUSE")
    return data


# ---------------------------------------------------------------------------
# 5. Statistics
# ---------------------------------------------------------------------------

def runs_frame(runs: list[pd.Series]) -> pd.DataFrame:
    """List of per-run Series -> DataFrame with index=day, columns=run."""
    return pd.DataFrame(runs).transpose()


def mean_ci(df_runs_T: pd.DataFrame, level: float = 1.96) -> tuple[pd.Series, pd.Series]:
    """Pointwise mean and 95% CI half-width across runs.

    Uses ddof=1 (sample std). With a single run the CI is zero-width.
    """
    mean_ = df_runs_T.mean(axis=1)
    n = df_runs_T.shape[1]
    if n > 1:
        ci = level * df_runs_T.std(axis=1, ddof=1) / np.sqrt(n)
    else:
        ci = pd.Series(np.zeros(len(mean_)), index=mean_.index)
    return mean_, ci


def pct_change_vs_baseline(data: dict, baseline: str) -> dict:
    """% change of each scenario's runs relative to the baseline *mean*.

    Note: treats the baseline mean as a fixed constant, so CI bands reflect
    scenario variance only (slightly anti-conservative). For paired designs
    prefer `paired_pct_change`.
    """
    out: dict[str, dict[str, pd.DataFrame]] = {}
    for v, runs_map in data.items():
        if baseline not in runs_map or not runs_map[baseline]:
            continue
        base_mean = runs_frame(runs_map[baseline]).mean(axis=1)
        out[v] = {}
        for scen, runs in runs_map.items():
            if scen == baseline or not runs:
                continue
            df = runs_frame(runs)
            out[v][scen] = df.sub(base_mean, axis=0).div(base_mean, axis=0).mul(100)
    return out


def paired_pct_change(data: dict, baseline: str) -> dict:
    """% change computed run-by-run: scenario run i vs baseline run i.

    Statistically cleaner when runs are paired (e.g. shared seeds), and it
    propagates baseline uncertainty into the CI.
    """
    out: dict[str, dict[str, pd.DataFrame]] = {}
    for v, runs_map in data.items():
        if baseline not in runs_map or not runs_map[baseline]:
            continue
        base_runs = runs_map[baseline]
        out[v] = {}
        for scen, runs in runs_map.items():
            if scen == baseline or not runs:
                continue
            cols = {}
            for i, (s_run, b_run) in enumerate(_pair_runs(runs, base_runs)):
                cols[i] = (s_run - b_run).div(b_run).mul(100)
            out[v][scen] = pd.DataFrame(cols)
    return out


# ---------------------------------------------------------------------------
# 6. Plotting
# ---------------------------------------------------------------------------

def scenario_style(cfg: Config, scen: str) -> tuple[str, tuple]:
    """Resolve (color, dash) for a scenario label with sensible fallbacks."""
    color = cfg.colors.get(scen)
    if color is None:
        color = "tab:blue" if "base" in scen.lower() else "tab:green"
    dash = cfg.dashes.get(scen, ())
    return color, dash


def plot_timeseries(
    runs_by_scenario: dict[str, "pd.DataFrame | list"],
    cfg: Config,
    var: str,
    ax: Optional[plt.Axes] = None,
    relative: bool = False,
    show_ci: bool = True,
    vlines: Sequence[float] = (),
    panel_tag: str = "",
) -> plt.Axes:
    """Plot one variable: mean lines +/- CI band per scenario.

    Parameters
    ----------
    runs_by_scenario : dict
        scenario -> DataFrame (index=day, columns=run) or list of Series.
    relative : bool
        If True, adds a horizontal 0-line and labels y as % change.
    vlines : sequence of x positions for vertical event markers.
    panel_tag : e.g. "(a)" printed top-left.
    """
    if ax is None:
        _, ax = plt.subplots(figsize=(6, 4))

    main_title, y_label = cfg.variable_titles.get(var, (var, var))

    for scen, runs in runs_by_scenario.items():
        df = runs if isinstance(runs, pd.DataFrame) else runs_frame(runs)
        if df.empty:
            continue
        m, ci = mean_ci(df)
        color, dash = scenario_style(cfg, scen)
        (line,) = ax.plot(m.index, m.values, label=scen, color=color, linewidth=1.6)
        if dash:
            line.set_dashes(dash)
        if show_ci and df.shape[1] > 1:
            ax.fill_between(m.index, (m - ci).values, (m + ci).values,
                            color=color, alpha=0.12)

    if relative:
        ax.axhline(0, linestyle="--", color="gray", linewidth=0.6)
        y_label = "% Change from Baseline"
    for x in vlines:
        ax.axvline(x, linestyle=(0, (6, 6)), color="gray", linewidth=0.8)
    if panel_tag:
        ax.text(0.02, 0.98, panel_tag, transform=ax.transAxes,
                ha="left", va="top", fontsize=14, fontweight="bold")

    ax.set_title(main_title, fontsize=12)
    ax.set_xlabel("Day", fontsize=10)
    ax.set_ylabel(y_label, fontsize=11)
    ax.legend(fontsize=9, framealpha=0.9)
    return ax


def plot_all_timeseries(
    data: dict,
    cfg: Config,
    out_dir: str,
    relative: bool = False,
    pdf_name: str = "all_plots.pdf",
    **plot_kwargs,
) -> None:
    """Loop over variables; save one PNG each + a combined PDF."""
    os.makedirs(out_dir, exist_ok=True)
    pdf_path = os.path.join(out_dir, pdf_name)

    with PdfPages(pdf_path) as pdf:
        for var, runs_map in data.items():
            available = {s: r for s, r in runs_map.items()
                         if (len(r.columns) if isinstance(r, pd.DataFrame) else len(r)) > 0}
            if not available:
                if cfg.verbose:
                    print(f"[skip] {var}: no data")
                continue
            fig, ax = plt.subplots(figsize=(6, 4))
            plot_timeseries(available, cfg, var, ax=ax, relative=relative, **plot_kwargs)
            plt.tight_layout()
            fig.savefig(os.path.join(out_dir, f"{var}.png"), dpi=300)
            pdf.savefig(fig, bbox_inches="tight")
            plt.close(fig)

    if cfg.verbose:
        print(f"[done] plots -> {os.path.abspath(out_dir)}; PDF -> {pdf_path}")


def save_standalone_legend(
    cfg: Config,
    labels: Sequence[str],
    out_path: str,
    figsize: tuple = (8, 1.5),
) -> None:
    """Save a horizontal legend-only figure for multi-panel compositions."""
    handles = []
    for lbl in labels:
        color, dash = scenario_style(cfg, lbl)
        line = Line2D([0], [0], color=color, lw=2)
        if dash:
            line.set_dashes(dash)
        handles.append(line)
    fig = plt.figure(figsize=figsize)
    fig.legend(handles, list(labels), loc="center", ncol=len(labels),
               frameon=False, fontsize=12)
    fig.patch.set_alpha(0.0)
    plt.axis("off")
    fig.savefig(out_path, dpi=300, bbox_inches="tight", pad_inches=0.1)
    plt.close(fig)


# ---------------------------------------------------------------------------
# 7. Neighborhood aggregation (choropleth support)
# ---------------------------------------------------------------------------

def build_neighborhood_groups(decoding_table: Sequence[tuple]) -> dict[str, list[int]]:
    """decoding_table rows: (row_index_1based, cbs_code, neighborhood_name).

    Returns neighborhood -> list of 0-based SA row indices.
    """
    groups: dict[str, list[int]] = {}
    for idx, (_, _, name) in enumerate(decoding_table):
        groups.setdefault(name, []).append(idx)
    return groups


def final_level_pct(last_val: float, base_val: float, eps: float = 1e-12) -> float:
    if not np.isfinite(base_val) or not np.isfinite(last_val):
        return np.nan
    return 100.0 * (last_val - base_val) / (abs(base_val) + eps)


def neighborhood_final_levels(
    raw: dict,
    groups: dict[str, list[int]],
    base_day_pos: int,
    exclude: Sequence[str] = (),
) -> pd.DataFrame:
    """Collapse per-SA run DataFrames to per-neighborhood final-level % change.

    Parameters
    ----------
    raw : data loaded with load_runs(cfg, aggregate=False):
          raw[var][scenario] = list of (SA x day) DataFrames.
    groups : from build_neighborhood_groups.
    base_day_pos : integer column position of the baseline day.
    exclude : neighborhood names to drop (e.g. industrial zones).

    Returns
    -------
    Long DataFrame: variable, scenario, neighborhood, run, pct_change.
    """
    rows = []
    keep = {n: idxs for n, idxs in groups.items() if n not in set(exclude)}
    for var, scen_map in raw.items():
        for scen, run_dfs in scen_map.items():
            for run_i, df in enumerate(run_dfs, start=1):
                for neigh, idxs in keep.items():
                    sub = df.iloc[idxs]
                    base = float(np.nanmean(sub.iloc[:, base_day_pos]))
                    last = float(np.nanmean(sub.iloc[:, -1]))
                    rows.append({
                        "variable": var, "scenario": scen,
                        "neighborhood": neigh, "run": run_i,
                        "pct_change": final_level_pct(last, base),
                    })
    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# 8. Scenario comparison / effect sizes
#    (foundation for "which parameter combination matters most")
# ---------------------------------------------------------------------------

def summarize_effects(
    data: dict,
    baseline: str,
    window: Optional[slice] = None,
) -> pd.DataFrame:
    """Rank scenarios by how strongly they deviate from baseline.

    For every (variable, scenario) computes, over the chosen day-window:
      mean_pct   : average % deviation from baseline mean
      final_pct  : % deviation on the last day
      max_abs_pct: largest absolute % deviation
      t_stat     : Welch t statistic on window-averaged runs
                   (scenario runs vs baseline runs)

    Returns a tidy DataFrame sorted by |t_stat| - a first-pass answer to
    "which scenario/parameter combination produces the most significant
    change on which outcome".
    """
    from scipy import stats as sps

    rows = []
    for var, runs_map in data.items():
        if baseline not in runs_map or not runs_map[baseline]:
            continue
        base_df = runs_frame(runs_map[baseline])
        if window is not None:
            base_df = base_df.iloc[window]
        base_run_means = base_df.mean(axis=0)          # one value per run
        base_mean_curve = base_df.mean(axis=1)

        for scen, runs in runs_map.items():
            if scen == baseline or not runs:
                continue
            df = runs_frame(runs)
            if window is not None:
                df = df.iloc[window]
            scen_run_means = df.mean(axis=0)

            pct_curve = (df.mean(axis=1) - base_mean_curve) / base_mean_curve * 100

            if len(scen_run_means) > 1 and len(base_run_means) > 1:
                t_stat, p_val = sps.ttest_ind(
                    scen_run_means, base_run_means, equal_var=False
                )
            else:
                t_stat, p_val = np.nan, np.nan

            rows.append({
                "variable": var,
                "scenario": scen,
                "mean_pct": pct_curve.mean(),
                "final_pct": pct_curve.iloc[-1] if len(pct_curve) else np.nan,
                "max_abs_pct": pct_curve.abs().max(),
                "t_stat": t_stat,
                "p_value": p_val,
                "n_runs_scen": len(scen_run_means),
                "n_runs_base": len(base_run_means),
            })

    out = pd.DataFrame(rows)
    if not out.empty:
        out = out.reindex(out["t_stat"].abs().sort_values(ascending=False).index)
    return out.reset_index(drop=True)
