from pathlib import Path

import duckdb
import japanize_matplotlib  # noqa: F401
import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.ticker import FuncFormatter

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data" / "processed"
FIGURE_DIR = ROOT / "figures"

ORDER_BASE = DATA_DIR / "order_base.parquet"
ITEM_BASE = DATA_DIR / "item_base.parquet"
CANDIDATE_RISK = DATA_DIR / "candidate_risk.parquet"
ALLOCATION = DATA_DIR / "allocation_recommendation.parquet"

plt.rcParams["svg.fonttype"] = "path"


def query_df(sql: str) -> pd.DataFrame:
    con = duckdb.connect()
    try:
        return con.execute(sql).df()
    finally:
        con.close()


def load_monthly_growth() -> pd.DataFrame:
    return query_df(f"""
        WITH o AS (
            SELECT purchase_month,
                   COUNT(DISTINCT order_id) AS placed_orders,
                   COUNT(DISTINCT customer_unique_id) AS active_customers
            FROM read_parquet('{ORDER_BASE.as_posix()}')
            GROUP BY 1
        ),
        i AS (
            SELECT purchase_month,
                   SUM(merchandise_value) AS merchandise_gmv,
                   COUNT(DISTINCT order_id) AS gmv_orders
            FROM read_parquet('{ITEM_BASE.as_posix()}')
            GROUP BY 1
        )
        SELECT o.*, i.merchandise_gmv, i.gmv_orders,
               i.merchandise_gmv / NULLIF(i.gmv_orders, 0) AS aov
        FROM o JOIN i USING (purchase_month)
        ORDER BY purchase_month
    """)


def plot_monthly_gmv(df: pd.DataFrame) -> None:
    df["purchase_month"] = pd.to_datetime(df["purchase_month"])
    fig, ax = plt.subplots(figsize=(10, 5.5))
    ax.plot(df["purchase_month"], df["merchandise_gmv"], marker="o", linewidth=2)
    ax.set_title("マーケットプレイスGMVは2017年に拡大し、2018年に横ばいへ", loc="left", fontsize=14, fontweight="bold")
    ax.set_ylabel("月次商品GMV（R$）")
    ax.set_xlabel("")
    ax.yaxis.set_major_formatter(FuncFormatter(lambda x, _: f"R${x / 1_000_000:.1f}M"))
    ax.grid(axis="y", alpha=0.25)
    fig.autofmt_xdate(rotation=45)
    fig.tight_layout()
    fig.savefig(FIGURE_DIR / "01_monthly_gmv.svg", bbox_inches="tight")
    plt.close(fig)


def load_category_opportunity() -> pd.DataFrame:
    return query_df(f"""
        WITH c AS (
            SELECT product_category_name_english AS category,
                   SUM(merchandise_value) FILTER (
                     WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
                       AND order_purchase_timestamp <  TIMESTAMP '2017-09-01') AS gmv_2017,
                   SUM(merchandise_value) FILTER (
                     WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
                       AND order_purchase_timestamp <  TIMESTAMP '2018-09-01') AS gmv_2018
            FROM read_parquet('{ITEM_BASE.as_posix()}')
            GROUP BY 1
        ),
        m AS (
            SELECT SUM(merchandise_value) FILTER (
                     WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
                       AND order_purchase_timestamp <  TIMESTAMP '2017-09-01') AS market_2017,
                   SUM(merchandise_value) FILTER (
                     WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
                       AND order_purchase_timestamp <  TIMESTAMP '2018-09-01') AS market_2018
            FROM read_parquet('{ITEM_BASE.as_posix()}')
        )
        SELECT c.category, c.gmv_2018,
               100.0 * (c.gmv_2018 - c.gmv_2017) / NULLIF(c.gmv_2017, 0) AS gmv_growth_pct,
               100.0 * (m.market_2018 - m.market_2017) / NULLIF(m.market_2017, 0) AS market_growth_pct
        FROM c CROSS JOIN m
        WHERE c.gmv_2017 > 0 AND c.gmv_2018 > 0
        ORDER BY c.gmv_2018 DESC
        LIMIT 20
    """)


def plot_category_opportunity(df: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(10, 6.5))
    ax.scatter(df["gmv_2018"], df["gmv_growth_pct"], s=70, alpha=0.8)
    market_growth = df["market_growth_pct"].iloc[0]
    ax.axhline(market_growth, linestyle="--", linewidth=1.5, alpha=0.7)
    for _, row in df.nlargest(8, "gmv_2018").iterrows():
        ax.annotate(row["category"], (row["gmv_2018"], row["gmv_growth_pct"]), xytext=(5, 5), textcoords="offset points", fontsize=8)
    ax.set_title("カテゴリ機会：規模と同期間成長を同時評価", loc="left", fontsize=14, fontweight="bold")
    ax.set_xlabel("2018年2–8月 商品GMV（R$）")
    ax.set_ylabel("同期間比較のGMV成長率（%）")
    ax.xaxis.set_major_formatter(FuncFormatter(lambda x, _: f"R${x / 1_000:.0f}k"))
    ax.grid(alpha=0.2)
    fig.tight_layout()
    fig.savefig(FIGURE_DIR / "02_category_opportunity.svg", bbox_inches="tight")
    plt.close(fig)


def load_candidate_risk() -> pd.DataFrame:
    return query_df(f"""
        SELECT category, customer_state,
               100 * late_delivery_rate AS late_delivery_rate_pct,
               100 * low_review_rate AS low_review_rate_pct,
               100 * market_late_delivery_rate AS market_late_delivery_rate_pct,
               100 * market_low_review_rate AS market_low_review_rate_pct,
               risk_eligible
        FROM read_parquet('{CANDIDATE_RISK.as_posix()}')
        ORDER BY risk_eligible DESC, category, customer_state
    """)


def plot_candidate_risk(df: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(10, 7))
    ax.scatter(df["late_delivery_rate_pct"], df["low_review_rate_pct"], s=60, alpha=0.75)
    market_late = df["market_late_delivery_rate_pct"].iloc[0]
    market_low = df["market_low_review_rate_pct"].iloc[0]
    ax.axvline(market_late, linestyle="--", linewidth=1.2, alpha=0.7)
    ax.axhline(market_low, linestyle="--", linewidth=1.2, alpha=0.7)
    for _, row in df.iterrows():
        if (not row["risk_eligible"]) or row["late_delivery_rate_pct"] < market_late - 2.0:
            label = f"{row['category']} × {row['customer_state']}"
            if not row["risk_eligible"]:
                label += "（除外）"
            ax.annotate(label, (row["late_delivery_rate_pct"], row["low_review_rate_pct"]), xytext=(5, 4), textcoords="offset points", fontsize=7)
    ax.set_title("機械選定候補のオペレーショナルリスク", loc="left", fontsize=14, fontweight="bold")
    ax.set_xlabel("遅配率（%）")
    ax.set_ylabel("低評価率（レビュー2以下、%）")
    ax.grid(alpha=0.2)
    fig.tight_layout()
    fig.savefig(FIGURE_DIR / "03_candidate_risk.svg", bbox_inches="tight")
    plt.close(fig)


def load_allocation() -> pd.DataFrame:
    return query_df(f"""
        SELECT category || ' × ' || customer_state AS segment, allocation_pct
        FROM read_parquet('{ALLOCATION.as_posix()}')
        ORDER BY priority_rank
    """)


def plot_allocation(df: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(9, 5.5))
    bars = ax.barh(df["segment"], df["allocation_pct"])
    ax.invert_yaxis()
    for bar, value in zip(bars, df["allocation_pct"]):
        ax.text(value + 0.4, bar.get_y() + bar.get_height() / 2, f"{value:.1f}%", va="center", fontsize=9)
    ax.set_title("機械選定後の推奨相対配分", loc="left", fontsize=14, fontweight="bold")
    ax.set_xlabel("相対的な資源配分（%）")
    ax.set_ylabel("")
    ax.xaxis.set_major_formatter(FuncFormatter(lambda x, _: f"{x:.0f}%"))
    ax.set_xlim(0, max(df["allocation_pct"]) * 1.18)
    ax.grid(axis="x", alpha=0.2)
    fig.tight_layout()
    fig.savefig(FIGURE_DIR / "04_recommended_allocation.svg", bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    FIGURE_DIR.mkdir(parents=True, exist_ok=True)
    plot_monthly_gmv(load_monthly_growth())
    plot_category_opportunity(load_category_opportunity())
    plot_candidate_risk(load_candidate_risk())
    plot_allocation(load_allocation())


if __name__ == "__main__":
    main()
