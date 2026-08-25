from pathlib import Path

import duckdb
import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.ticker import FuncFormatter


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data" / "processed"
FIGURE_DIR = ROOT / "figures"

ORDER_BASE = DATA_DIR / "order_base.parquet"
ITEM_BASE = DATA_DIR / "item_base.parquet"


def load_monthly_growth() -> pd.DataFrame:
    con = duckdb.connect()

    query = f"""
    WITH order_metrics AS (
        SELECT
            purchase_month,
            COUNT(DISTINCT order_id) AS placed_orders,
            COUNT(DISTINCT customer_unique_id) AS active_customers
        FROM read_parquet('{ORDER_BASE.as_posix()}')
        GROUP BY purchase_month
    ),

    item_metrics AS (
        SELECT
            purchase_month,
            SUM(merchandise_value) AS merchandise_gmv,
            COUNT(DISTINCT order_id) AS gmv_orders
        FROM read_parquet('{ITEM_BASE.as_posix()}')
        GROUP BY purchase_month
    )

    SELECT
        o.purchase_month,
        o.placed_orders,
        o.active_customers,
        i.merchandise_gmv,
        i.gmv_orders,
        i.merchandise_gmv
            / NULLIF(i.gmv_orders, 0) AS aov
    FROM order_metrics o
    JOIN item_metrics i USING (purchase_month)
    ORDER BY purchase_month
    """

    df = con.execute(query).df()
    con.close()

    df["purchase_month"] = pd.to_datetime(df["purchase_month"])

    return df


def plot_monthly_gmv(df: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(10, 5.5))

    ax.plot(
        df["purchase_month"],
        df["merchandise_gmv"],
        marker="o",
        linewidth=2,
    )

    ax.set_title(
        "Marketplace GMV accelerated in 2017 before plateauing in 2018",
        loc="left",
        fontsize=14,
        fontweight="bold",
    )

    ax.set_xlabel("")
    ax.set_ylabel("Monthly merchandise GMV (R$)")

    ax.yaxis.set_major_formatter(
        FuncFormatter(lambda x, _: f"R${x / 1_000_000:.1f}M")
    )

    ax.grid(axis="y", alpha=0.25)

    fig.autofmt_xdate(rotation=45)
    fig.tight_layout()

    output_path = FIGURE_DIR / "01_monthly_gmv.png"
    fig.savefig(output_path, dpi=180, bbox_inches="tight")
    plt.close(fig)

    print(f"Saved: {output_path}")


def load_category_opportunity() -> pd.DataFrame:
    con = duckdb.connect()

    query = f"""
    WITH category_metrics AS (
        SELECT
            product_category_name_english AS category,

            SUM(merchandise_value) FILTER (
                WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
                  AND order_purchase_timestamp <  TIMESTAMP '2017-09-01'
            ) AS gmv_2017,

            SUM(merchandise_value) FILTER (
                WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
                  AND order_purchase_timestamp <  TIMESTAMP '2018-09-01'
            ) AS gmv_2018

        FROM read_parquet('{ITEM_BASE.as_posix()}')
        GROUP BY product_category_name_english
    ),

    market_metrics AS (
        SELECT
            SUM(merchandise_value) FILTER (
                WHERE order_purchase_timestamp >= TIMESTAMP '2017-02-01'
                  AND order_purchase_timestamp <  TIMESTAMP '2017-09-01'
            ) AS market_gmv_2017,

            SUM(merchandise_value) FILTER (
                WHERE order_purchase_timestamp >= TIMESTAMP '2018-02-01'
                  AND order_purchase_timestamp <  TIMESTAMP '2018-09-01'
            ) AS market_gmv_2018

        FROM read_parquet('{ITEM_BASE.as_posix()}')
    )

    SELECT
        c.category,
        c.gmv_2017,
        c.gmv_2018,

        100.0
        * (c.gmv_2018 - c.gmv_2017)
        / NULLIF(c.gmv_2017, 0) AS gmv_growth_pct,

        100.0
        * (m.market_gmv_2018 - m.market_gmv_2017)
        / NULLIF(m.market_gmv_2017, 0) AS market_growth_pct

    FROM category_metrics c
    CROSS JOIN market_metrics m

    WHERE c.gmv_2017 IS NOT NULL
      AND c.gmv_2018 IS NOT NULL

    ORDER BY c.gmv_2018 DESC
    LIMIT 20
    """

    df = con.execute(query).df()
    con.close()

    return df


def plot_category_opportunity(df: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(10, 6.5))

    ax.scatter(
        df["gmv_2018"],
        df["gmv_growth_pct"],
        s=70,
        alpha=0.8,
    )

    market_growth = df["market_growth_pct"].iloc[0]

    ax.axhline(
        market_growth,
        linestyle="--",
        linewidth=1.5,
        alpha=0.7,
    )

    candidate_categories = {
    "health_beauty",
    "watches_gifts",
    "housewares",
    "auto",
    "baby",
    }

    for _, row in df.iterrows():
        if row["category"] in candidate_categories:
            ax.annotate(
                row["category"],
                (row["gmv_2018"], row["gmv_growth_pct"]),
                xytext=(6, 6),
                textcoords="offset points",
                fontsize=9,
            )


    # Label the highest-growth category separately.
    # This is a low-base outlier and should not be interpreted
    # as the strongest investment opportunity based on growth rate alone.
    outlier = df.loc[df["gmv_growth_pct"].idxmax()]

    ax.annotate(
        f"{outlier['category']}\n(low-base outlier)",
        (outlier["gmv_2018"], outlier["gmv_growth_pct"]),
        xytext=(10, -5),
        textcoords="offset points",
        fontsize=9,
        va="top",
    )

    ax.set_title(
        "The strongest categories combine scale with above-market growth",
        loc="left",
        fontsize=14,
        fontweight="bold",
    )

    ax.set_xlabel("Feb–Aug 2018 merchandise GMV (R$)")
    ax.set_ylabel("Comparable-period GMV growth (%)")

    ax.xaxis.set_major_formatter(
        FuncFormatter(lambda x, _: f"R${x / 1_000:.0f}k")
    )

    ax.yaxis.set_major_formatter(
        FuncFormatter(lambda y, _: f"{y:.0f}%")
    )

    ax.text(
        df["gmv_2018"].max() * 0.72,
        market_growth + 10,
        f"Market growth: {market_growth:.0f}%",
        fontsize=9,
    )

    ax.grid(alpha=0.2)

    fig.tight_layout()

    output_path = FIGURE_DIR / "02_category_opportunity.png"
    fig.savefig(output_path, dpi=180, bbox_inches="tight")
    plt.close(fig)

    print(f"Saved: {output_path}")


def load_candidate_risk() -> pd.DataFrame:
    con = duckdb.connect()

    query = f"""
    WITH candidate_segments AS (
        SELECT *
        FROM (
            VALUES
                ('health_beauty', 'SP'),
                ('health_beauty', 'MG'),
                ('housewares',    'SP'),
                ('watches_gifts', 'SP'),
                ('watches_gifts', 'RJ')
        ) AS t(category, customer_state)
    ),

    candidate_orders AS (
        SELECT DISTINCT
            i.product_category_name_english AS category,
            i.customer_state,
            i.order_id
        FROM read_parquet('{ITEM_BASE.as_posix()}') i
        JOIN candidate_segments c
          ON i.product_category_name_english = c.category
         AND i.customer_state = c.customer_state
    ),

    market_risk AS (
        SELECT
            100.0
            * COUNT(*) FILTER (
                WHERE late_delivery_eligible
                  AND late_delivery_flag
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE late_delivery_eligible
                ),
                0
            ) AS market_late_delivery_rate_pct,

            100.0
            * COUNT(*) FILTER (
                WHERE review_eligible
                  AND review_score <= 2
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE review_eligible
                ),
                0
            ) AS market_low_review_rate_pct

        FROM read_parquet('{ORDER_BASE.as_posix()}')
    ),

    candidate_risk AS (
        SELECT
            c.category,
            c.customer_state,

            100.0
            * COUNT(*) FILTER (
                WHERE o.late_delivery_eligible
                  AND o.late_delivery_flag
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE o.late_delivery_eligible
                ),
                0
            ) AS late_delivery_rate_pct,

            100.0
            * COUNT(*) FILTER (
                WHERE o.review_eligible
                  AND o.review_score <= 2
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE o.review_eligible
                ),
                0
            ) AS low_review_rate_pct

        FROM candidate_orders c

        JOIN read_parquet('{ORDER_BASE.as_posix()}') o
          USING (order_id)

        GROUP BY
            c.category,
            c.customer_state
    )

    SELECT
        r.category,
        r.customer_state,
        r.late_delivery_rate_pct,
        r.low_review_rate_pct,
        m.market_late_delivery_rate_pct,
        m.market_low_review_rate_pct

    FROM candidate_risk r
    CROSS JOIN market_risk m

    ORDER BY
        r.category,
        r.customer_state
    """

    df = con.execute(query).df()
    con.close()

    return df


def plot_candidate_risk(df: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(9, 6.5))

    ax.scatter(
        df["late_delivery_rate_pct"],
        df["low_review_rate_pct"],
        s=100,
        alpha=0.85,
    )

    market_late = df["market_late_delivery_rate_pct"].iloc[0]
    market_low_review = df["market_low_review_rate_pct"].iloc[0]

    ax.axvline(
        market_late,
        linestyle="--",
        linewidth=1.5,
        alpha=0.7,
    )

    ax.axhline(
        market_low_review,
        linestyle="--",
        linewidth=1.5,
        alpha=0.7,
    )

    label_offsets = {
        ("health_beauty", "SP"): (8, -2),
        ("health_beauty", "MG"): (8, 10),
        ("housewares", "SP"): (8, -14),
        ("watches_gifts", "SP"): (8, 7),
        ("watches_gifts", "RJ"): (-115, -5),
    }

    for _, row in df.iterrows():
        key = (row["category"], row["customer_state"])
        x_offset, y_offset = label_offsets[key]

        label = f"{row['category']} × {row['customer_state']}"

        if key == ("watches_gifts", "RJ"):
            label += "\n(excluded)"

        ax.annotate(
            label,
            (
                row["late_delivery_rate_pct"],
                row["low_review_rate_pct"],
            ),
            xytext=(x_offset, y_offset),
            textcoords="offset points",
            fontsize=9,
            va="top" if key == ("watches_gifts", "RJ") else "baseline",
        )
        

    ax.text(
        market_late + 0.2,
        ax.get_ylim()[0] + 0.3,
        f"Market late delivery: {market_late:.1f}%",
        fontsize=9,
        rotation=90,
        va="bottom",
    )

    ax.text(
        ax.get_xlim()[0] + 0.2,
        market_low_review + 0.3,
        f"Market low-review rate: {market_low_review:.1f}%",
        fontsize=9,
    )

    ax.set_title(
        "Most shortlisted segments outperform market risk benchmarks",
        loc="left",
        fontsize=14,
        fontweight="bold",
    )

    ax.set_xlabel("Late delivery rate (%)")
    ax.set_ylabel("Low-review rate (%)")

    ax.xaxis.set_major_formatter(
        FuncFormatter(lambda x, _: f"{x:.0f}%")
    )

    ax.yaxis.set_major_formatter(
        FuncFormatter(lambda y, _: f"{y:.0f}%")
    )

    ax.grid(alpha=0.2)

    fig.tight_layout()

    output_path = FIGURE_DIR / "03_candidate_risk.png"
    fig.savefig(output_path, dpi=180, bbox_inches="tight")
    plt.close(fig)

    print(f"Saved: {output_path}")
    
    

ALLOCATION = DATA_DIR / "allocation_recommendation.parquet"


def load_allocation() -> pd.DataFrame:
    con = duckdb.connect()

    query = f"""
    SELECT
        category || ' × ' || customer_state AS segment,
        allocation_pct
    FROM read_parquet('{ALLOCATION.as_posix()}')
    ORDER BY allocation_pct DESC
    """

    df = con.execute(query).df()
    con.close()

    return df


def plot_allocation(df: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(9, 5.5))

    bars = ax.barh(
        df["segment"],
        df["allocation_pct"],
    )

    ax.invert_yaxis()

    for bar, value in zip(bars, df["allocation_pct"]):
        ax.text(
            value + 0.7,
            bar.get_y() + bar.get_height() / 2,
            f"{value:.0f}%",
            va="center",
            fontsize=10,
        )

    ax.set_title(
        "Recommended allocation prioritizes resilient high-growth segments",
        loc="left",
        fontsize=14,
        fontweight="bold",
    )

    ax.set_xlabel("Relative resource allocation (%)")
    ax.set_ylabel("")

    ax.xaxis.set_major_formatter(
        FuncFormatter(lambda x, _: f"{x:.0f}%")
    )

    ax.set_xlim(0, max(df["allocation_pct"]) * 1.18)

    ax.grid(axis="x", alpha=0.2)

    fig.tight_layout()

    output_path = FIGURE_DIR / "04_recommended_allocation.png"
    fig.savefig(output_path, dpi=180, bbox_inches="tight")
    plt.close(fig)

    print(f"Saved: {output_path}")



def main() -> None:
    FIGURE_DIR.mkdir(parents=True, exist_ok=True)

    monthly_growth = load_monthly_growth()
    plot_monthly_gmv(monthly_growth)

    category_opportunity = load_category_opportunity()
    plot_category_opportunity(category_opportunity)

    candidate_risk = load_candidate_risk()
    plot_candidate_risk(candidate_risk)

    allocation = load_allocation()
    plot_allocation(allocation)


if __name__ == "__main__":
    main()