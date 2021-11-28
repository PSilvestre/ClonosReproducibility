import math
import sys
from typing import List, Tuple

import matplotlib
import matplotlib.patches as mpatches
import numpy as np
import pandas as pd
from matplotlib import pyplot as plt


def failure_get_killtimes(path: str):
    killtimes = []
    with open(path) as f:
        for line in f.readlines():
            if not line.isspace():
                killtimes.append(int(line.strip().split(" ")[3]))

    return killtimes


def lowpass_smooth(data: pd.Series, alpha: float):
    data_filtered = []
    for i, val in enumerate(data):
        if i != 0 and i != len(data) - 1:
            data_filtered.append(alpha * data[i - 1] + (1 - 2 * alpha) * val + alpha * data[i + 1])
    return pd.Series(data_filtered)


def failure_latency_compare(save_name: str, latencies: List[pd.DataFrame], killtimes: List[int],
                            time_range: Tuple[int, int]):
    # TODO recovery anotations
    matplotlib.rcParams.update({'font.size': 16})
    linestyles = ["", ""]
    markers = ["+", "x"]
    colors = ["teal", "crimson"]
    names = ["Clonos", "Flink"]

    num_partitions = int(len(latencies[0].columns) / 4)

    fig, axs = plt.subplots(2, sharex=True)

    max_lat = max([max([df[f"LATENCY-{p}"].max() for p in range(num_partitions)]) for df in latencies]) / 1000

    killtimes_adjusted = []
    for i, df in enumerate(latencies):
        init_ts = int(min(df[f"OUTPUT-{p}"].min() for p in range(num_partitions)))
        if i == 0:
            for kill in killtimes:
                killtimes_adjusted.append((kill - init_ts) / 1000)

        # Normalize record emission time columns

        for column in df.columns:
            if not str(column).startswith("OUTPUT-"):
                df[column] = df[column] / 1000

        for p in range(num_partitions):
            df[f"OUTPUT-{p}"] = df[f"OUTPUT-{p}"] / 1000 - init_ts / 1000

        #Anotate graph with recovery time
        last_fail = max(killtimes_adjusted)
        recovered = compute_recovered_timestamp(df, last_fail, num_partitions, time_range)
        axs[i].annotate("", xy=(last_fail, max_lat / 4 * 1), xycoords='data',
                        xytext=(recovered, max_lat / 4 * 1), textcoords='data',
                        arrowprops=dict(arrowstyle="|-|", color="green"))
        text_str = f"{round(recovered - last_fail)}s{'+' if recovered == time_range[1] else ''}"
        axs[i].text(last_fail + (time_range[1] - time_range[0]) * 0.02, max_lat / 4 * 1.1, text_str, fontsize=12)

        for kill in killtimes_adjusted:
            axs[i].axvline(kill, color="r", linestyle="--")
        # axs[i].set_ylim([0, max_lat])
        axs[i].set_ylim([0, 35])
        axs[i].set_yticks(list(range(0, 35, 5)))
        axs[i].grid(axis="y")
        axs[i].set_xlim(time_range)
        for p in range(num_partitions):
            label_arg = {"label": names[i] if p == 0 else None}
            axs[i].plot(df[f"OUTPUT-{p}"], df[f"LATENCY-{p}"],
                        alpha=0.8,
                        linestyle=linestyles[i], color=colors[i], marker=markers[i], linewidth=1,
                        **label_arg, markersize=4)
        axs[i].set(ylabel="Latency (s)")
        axs[i].legend(loc="upper right", prop={'size': 16})

    plt.xlabel("Experiment Time (s)")

    fig.tight_layout(pad=0.05)
    plt.savefig(save_name,
                bbox_inches="tight",
                # pad_inches=0.05,
                # transparent=True
                )
    plt.close()


def compute_recovered_timestamp(df, last_fail, num_partitions, time_range):
    merged = merge_latency_df(df, num_partitions)
    pre_failure_lats = merged.query("TIME < 40")["LAT"]
    avg_lat = pre_failure_lats.mean()
    std_dev_lat = pre_failure_lats.std()
    limit_lat = avg_lat + 1.1 * std_dev_lat

    # Compute a time-based rolling average of latency
    merged = merged.query(f"TIME > {time_range[0] - 5} & TIME < {time_range[1] + 5}")
    datetime_merged = merged.copy()
    datetime_merged["TIME"] = merged["TIME"].map(lambda x: pd.Timestamp(x, unit="s"))

    rolling_avg = datetime_merged.sort_values(by="TIME").rolling("10s", on="TIME").mean()

    fail_ts = pd.Timestamp(last_fail + 2, unit='s')
    above_lat_limit_times = rolling_avg.query(f"TIME > @fail_ts & LAT > @limit_lat")["TIME"]

    result = merged.query(f"TIME > {last_fail}")["TIME"].min()  # Assume instant recovery if no effect on latency
    if not pd.isnull(above_lat_limit_times.max()):  # If there are latency values above limit
        result = above_lat_limit_times.max().timestamp() - 5  # compensate for window value being set on the right bound
    return result


def merge_latency_df(df, num_partitions):
    times = []
    lats = []
    for p in range(num_partitions):
        times.extend(list(df[f"OUTPUT-{p}"]))
        lats.extend(list(df[f"LATENCY-{p}"]))
    # TODO Q8 flink too short.
    merged = pd.DataFrame({"TIME": times, "LAT": lats})
    return merged


def failure_throughput_compare(save_path: str, thrs: List[pd.DataFrame], killtimes: List[int],
                               time_range: Tuple[int, int], normalizer: int,
                               ylabel: str = "Throughput (M Records/second)", input_thr: int = 0):
    matplotlib.rcParams.update({'font.size': 16})
    fig = plt.figure()

    colors = ["teal", "crimson"]
    labels = ["Clonos", "Flink"]
    markers = [".", "x"]

    init_times = []
    for i, df in enumerate(thrs):
        init_ts = df["TIME"].iloc[0]
        init_times.append(init_ts)
        # ms -> s and start from 0
        df["TIME"] = df["TIME"] / 1000 - init_ts / 1000
        # Normalize and smooth throughput
        df["THROUGHPUT"] = lowpass_smooth(df["THROUGHPUT"] / normalizer, 0.3)
        df = df.iloc[::1]  # Thin it out, skipping every one record
        df = df.query(f"TIME > {time_range[0]} & TIME < {time_range[1]}")  # Focus on interesting area of the graph
        thrs[i] = df

    # TODO generate pretty numbers...
    ymax = round(max(thrs[0]["THROUGHPUT"].max(), thrs[1]["THROUGHPUT"].max()) * 1.1, ndigits=2)
    y_ticks = arange_pretty(ymax)
    plt.ylim([y_ticks[0], y_ticks[-1]])
    plt.yticks(y_ticks)
    plt.xlim(time_range)
    plt.grid(axis="y")

    for i, df in enumerate(thrs):
        plt.plot(df["TIME"], df["THROUGHPUT"], label=labels[i], alpha=0.8,
                 linestyle="-", color=colors[i], marker=markers[i], linewidth=1, markersize=4)
        if i == 0:
            for kill in killtimes:
                plt.axvline((kill - init_times[i]) / 1000, color="r", linestyle="--")

    if input_thr != 0:
        plt.axhline(input_thr, color="grey", linestyle="--")

    plt.xlabel("Experiment Time (s)")
    plt.ylabel(ylabel)
    plt.legend(prop={'size': 16})
    fig.tight_layout(pad=0.05)
    plt.savefig(save_path, bbox_inches="tight")
    plt.close()


def arange_pretty(ymax):
    n_digit = len(str(int(ymax)))
    norm_to_1_digit = 10 ** (n_digit - 1)
    # find next even number
    even = math.ceil(ymax / norm_to_1_digit)

    if even <= 1:
        y_ticks = list(np.arange(0, even, 0.1) * norm_to_1_digit)
    elif even <= 5:
        y_ticks = list(np.arange(0, even, 0.25) * norm_to_1_digit)
    else:
        y_ticks = list(np.arange(0, even, 0.5) * norm_to_1_digit)

    return y_ticks


def draw_overhead_experiment_graph(file: str, save_path: str):
    df = pd.read_csv(file, sep="\s+")
    df_flink = df.query("SYSTEM == 'flink'").copy().sort_values(by='QUERY')
    df_clonos_dsd_1 = df.query("SYSTEM == 'clonos' & DSD == 1").copy().sort_values(by='QUERY')
    df_clonos_dsd_neg1 = df.query("SYSTEM == 'clonos' & DSD == -1").copy().sort_values(by='QUERY')

    df_flink["REL_THROUGHPUT"] = 1.0

    df_clonos_dsd_1["REL_THROUGHPUT"] = np.clip(
        df_clonos_dsd_1["THROUGHPUT"].to_numpy() / df_flink["THROUGHPUT"].to_numpy(), 0, 1)
    df_clonos_dsd_neg1["REL_THROUGHPUT"] = np.clip(
        df_clonos_dsd_neg1["THROUGHPUT"].to_numpy() / df_flink["THROUGHPUT"].to_numpy(), 0, 1)

    # If relative throughput Clonos exceeds 1.0 we consider it noise and just set it to 1.

    fig, ax = plt.subplots(figsize=(14, 3), nrows=1, ncols=1)
    barwidth = 0.2
    queries = df["QUERY"].unique()
    x = np.arange(len(queries))

    ax.set_xticks(x + barwidth)
    ax.set_yticks([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0])
    ax.set_yticklabels(str(x) for x in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0])
    ax.set_xticklabels([f"Q{q}" for q in queries])

    ax.set_axisbelow(True)
    plt.grid(axis="y")

    ax.bar(x, df_flink["REL_THROUGHPUT"], barwidth, label="Flink", alpha=0.99,
           hatch="", color="crimson", linewidth=1, edgecolor="black")

    ax.bar(x + barwidth, df_clonos_dsd_1["REL_THROUGHPUT"], barwidth, label="Clonos (DSD=1)", alpha=0.99,
           hatch="...", color="aqua", linewidth=1, edgecolor="black")
    ax.bar(x + barwidth * 2, df_clonos_dsd_neg1["REL_THROUGHPUT"], barwidth, label="Clonos (DSD=Full)",
           alpha=0.99,
           hatch="\\\\\\", color="deepskyblue", linewidth=1, edgecolor="black")

    rect = mpatches.Rectangle((-0.1, 0.1), 12.6, 0.22,
                              fill=True,
                              color="white",
                              alpha=0.8,
                              linewidth=0)
    plt.gca().add_patch(rect)
    for bar in ax.patches:
        if bar.get_width() < bar.get_height():
            bar_value = bar.get_height()
            text = f'{bar_value:.2f}'
            text_x = bar.get_x() + bar.get_width() / 2
            text_y = bar.get_y() + 1 / 8
            bar_color = "black"
            # If you want a consistent color, you can just set it as a constant, e.g. #222222
            ax.text(text_x, text_y, text, ha='center', va='bottom', color=bar_color, size=12, rotation="vertical")

    # ax.set_ylabel("Relative Throughput")
    # ax.set_xlabel("Query")
    # ax.set_xticks(x)
    ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.075), fancybox=False, shadow=False, ncol=5)

    fig.tight_layout()
    plt.savefig(save_path, bbox_inches="tight", dpi=fig.dpi * 2)

    plt.close()


def draw_nexmark_fail_experiment_graph(input_path: str, output_path: str):
    for q in ["q3", "q8"]:
        clonos_thr = pd.read_csv(f"{input_path}/clonos/{q}/throughput", sep="\s+")
        clonos_lat = pd.read_csv(f"{input_path}/clonos/{q}/latency", sep="\s+")
        kts = failure_get_killtimes(f"{input_path}/clonos/{q}/killtime")

        flink_thr = pd.read_csv(f"{input_path}/flink/{q}/throughput", sep="\s+")
        flink_lat = pd.read_csv(f"{input_path}/flink/{q}/latency", sep="\s+")

        failure_throughput_compare(output_path + "/" + q + "_failure_throughput.pdf", [clonos_thr, flink_thr], kts,
                                   time_range=(30, 160), normalizer=1000, ylabel="Throughput (K Records/second)",
                                   input_thr=0)
        failure_latency_compare(f"{output_path}/{q}_failure_latency.pdf", [clonos_lat, flink_lat], kts,
                                time_range=(30, 160))


def draw_synthetic_fail_experiment_graph(input_path: str, output_path: str):
    for fail_type in ["multiple", "concurrent"]:
        clonos_thr = pd.read_csv(f"{input_path}/clonos/fail_{fail_type}/throughput", sep="\s+")
        clonos_lat = pd.read_csv(f"{input_path}/clonos/fail_{fail_type}/latency", sep="\s+")
        kts = failure_get_killtimes(f"{input_path}/clonos/fail_{fail_type}/killtime")

        flink_thr = pd.read_csv(f"{input_path}/flink/fail_{fail_type}/throughput", sep="\s+")
        flink_lat = pd.read_csv(f"{input_path}/flink/fail_{fail_type}/latency", sep="\s+")

        max_thr_measured = max(clonos_thr["THROUGHPUT"].max(), flink_thr["THROUGHPUT"].max())

        failure_throughput_compare(output_path + "/" + fail_type + "_failure_throughput.pdf", [clonos_thr, flink_thr],
                                   kts,
                                   time_range=(30, 200), normalizer=1000000,
                                   ylabel="Throughput (M Records/second)", input_thr=0.25)  # TODO input thr
        failure_latency_compare(f"{output_path}/{fail_type}_failure_latency.pdf", [clonos_lat, flink_lat], kts,
                                time_range=(30, 200))


def main():
    if len(sys.argv) != 3:
        print(f"Error! Usage: python3 {sys.argv[0]} path_to_results_directory path_to_figures_directory")
        exit(1)

    # Avoid type 3 fonts
    matplotlib.rcParams['pdf.fonttype'] = 42
    matplotlib.rcParams['ps.fonttype'] = 42

    input_path: str = sys.argv[1]
    output_path: str = sys.argv[2]

    draw_overhead_experiment_graph(input_path + "/nexmark_overhead", output_path + "/overhead.pdf")
    draw_nexmark_fail_experiment_graph(input_path + "/nexmark_failure", output_path)
    draw_synthetic_fail_experiment_graph(input_path + "/synthetic_failure", output_path)


if __name__ == "__main__":
    main()
