#!/usr/bin/env python3
"""Plot prefetch limit sweep results for littlex5 (sweep_prefetch_limit.csv).

Two side-by-side bars per prefetch_limit:

  * LEFT — E2E stack: walker + ttg + topo + misc.  Total height = e2e.
           Prefetch is intentionally excluded from the stack because
           under `async_prefetch="thread"` it overlaps with walker time
           and stacking would double-count.
  * RIGHT — Prefetcher wall time (max across per-worker durations
            recorded by TieredMemory.prefetch).  Standalone bar so
            the reader can see, at a glance, how much of the walker
            phase the prefetch was still running for.

CSV format:
    walker,prefetch_limit,trial,e2e_ms,topo_idx_ms,ttg_ms,
    prefetch_ms,walker_ms,l1_hit_rate,l1,l2,l3,miss,mongo_q

(prefetch_ms here is real wall time — the max per-worker duration —
after the runtime fix in `impl/memory.impl.jac`.)
"""

import os
import sys
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


def main():
    csv_file = sys.argv[1] if len(sys.argv) > 1 else "sweep_prefetch_limit.csv"
    app_name = os.path.basename(os.path.abspath(os.path.dirname(csv_file))).title()

    df = pd.read_csv(csv_file)
    numeric_cols = [
        "prefetch_limit", "trial", "e2e_ms",
        "topo_idx_ms", "ttg_ms", "prefetch_ms", "walker_ms",
        "l1_hit_rate",
    ]
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    walkers = sorted(df["walker"].unique())
    has_breakdown = all(
        c in df.columns
        for c in ["topo_idx_ms", "ttg_ms", "prefetch_ms", "walker_ms"]
    )
    has_hit_rate = "l1_hit_rate" in df.columns

    fig, axes = plt.subplots(1, len(walkers), figsize=(8 * len(walkers), 6))
    if len(walkers) == 1:
        axes = [axes]

    for ax, walker in zip(axes, walkers):
        wdf = df[df["walker"] == walker]
        grouped = wdf.groupby("prefetch_limit").median(numeric_only=True).reset_index()
        grouped = grouped.sort_values("prefetch_limit")

        n = len(grouped)
        group_x = np.arange(n)
        # Two side-by-side bars per group: e2e stack (left), prefetch (right).
        bar_w = 0.38
        x_e2e = group_x - bar_w / 2
        x_pf = group_x + bar_w / 2

        if has_breakdown and not grouped["walker_ms"].isna().all():
            ew = grouped["walker_ms"].fillna(0).values
            eg = grouped["ttg_ms"].fillna(0).values
            et = grouped["topo_idx_ms"].fillna(0).values
            ee = grouped["e2e_ms"].fillna(0).values
            # Misc = e2e minus the accounted-for additive components.
            # Prefetch is NOT subtracted here — it's overlapping with
            # walker time under thread mode and its share is already
            # baked into walker_ms.
            em = np.maximum(ee - (ew + eg + et), 0)

            # LEFT bar: e2e stack.
            ax.bar(x_e2e, ew, bar_w, label="Walker", color="steelblue")
            ax.bar(x_e2e, eg, bar_w, bottom=ew, label="TTG Generator", color="seagreen")
            ax.bar(x_e2e, et, bar_w, bottom=ew + eg, label="Load topology", color="purple")
            ax.bar(x_e2e, em, bar_w, bottom=ew + eg + et, label="Misc", color="lightgray")

            for i, total in enumerate(ee):
                ax.text(
                    x_e2e[i], total + 5, f"{total:.0f}",
                    ha="center", va="bottom",
                    fontsize=8, fontweight="bold", color="black",
                )

            # RIGHT bar: prefetch wall time only.
            ep = grouped["prefetch_ms"].fillna(0).values
            ax.bar(x_pf, ep, bar_w, label="Prefetcher (wall)", color="orange")

            for i, val in enumerate(ep):
                ax.text(
                    x_pf[i], val + 5, f"{val:.0f}",
                    ha="center", va="bottom",
                    fontsize=8, fontweight="bold", color="darkorange",
                )
        else:
            # Fallback: just e2e bars, no per-phase breakdown available.
            ee = grouped["e2e_ms"].fillna(0).values
            ax.bar(group_x, ee, 0.6, color="steelblue", alpha=0.85, label="E2E")
            for i, total in enumerate(ee):
                ax.text(
                    group_x[i], total + 5, f"{total:.0f}ms",
                    ha="center", va="bottom",
                    fontsize=9, fontweight="bold",
                )

        ax.set_xlabel("Prefetch Limit")
        ax.set_xticks(group_x)
        ax.set_xticklabels([str(int(v)) for v in grouped["prefetch_limit"].values])
        ax.set_title(f"Walker: {walker}")
        ax.grid(axis="y", alpha=0.3)

        if has_hit_rate and not grouped["l1_hit_rate"].isna().all():
            ax2 = ax.twinx()
            hit = grouped["l1_hit_rate"].fillna(0).values
            ax2.plot(
                group_x, hit,
                color="crimson", marker="o", linewidth=2,
                label="L1 hit rate",
            )
            ax2.set_ylabel("L1 hit rate (%)", color="crimson")
            ax2.set_ylim(0, 105)
            ax2.tick_params(axis="y", labelcolor="crimson")
            for i, val in enumerate(hit):
                ax2.text(
                    group_x[i], val + 2, f"{val:.0f}%",
                    ha="center", va="bottom",
                    fontsize=8, color="crimson",
                )

    axes[0].set_ylabel("Time (ms)")
    if has_breakdown:
        axes[-1].legend(loc="upper left", bbox_to_anchor=(1.02, 1), borderaxespad=0)
    subtitle_bits = [
        "left bar = e2e stack",
        "right bar = prefetch wall time",
    ]
    if has_hit_rate:
        subtitle_bits.append("red line = L1 hit rate (%, right axis)")
    subtitle_bits.append("cold Redis, median")
    fig.suptitle(
        f"{app_name} E2E vs Prefetch Limit  ·  " + "  ·  ".join(subtitle_bits),
        fontsize=11, fontweight="bold",
    )
    plt.tight_layout()

    output_file = csv_file.replace(".csv", ".png")
    plt.savefig(output_file, dpi=150, bbox_inches="tight")
    print(f"Saved plot to {output_file}")


if __name__ == "__main__":
    main()
