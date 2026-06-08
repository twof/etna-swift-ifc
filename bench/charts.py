#!/usr/bin/env python3
# Render the IFC benchmark: normalized executions-to-find buckets + a per-engine
# summary table. Reads bench/results/{ptk,qc-bespoke,qc-derived}.tsv (one row per
# mutant per trial: mutant<TAB>trial<TAB>execs<TAB>seconds[<TAB>status]) and
# collapses trials to a per-mutant median before bucketing.
import os, statistics
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "results")
FIG = os.path.abspath(os.path.join(HERE, "..", "figures"))
os.makedirs(FIG, exist_ok=True)

ENGINES = [("swift / ptk", "ptk.tsv"),
           ("quickchick / bespoke", "qc-bespoke.tsv"),
           ("quickchick / derived", "qc-derived.tsv")]

def load(fn):
    # -> {mutant: ([execs...], [secs...])}
    by = {}
    for line in open(os.path.join(RES, fn)):
        p = line.split("\t")
        if len(p) < 4: continue
        m = int(p[0]); execs = int(p[2]); secs = float(p[3])
        e, s = by.setdefault(m, ([], []))
        e.append(execs); s.append(secs)
    return by

def medians(by):
    # per-mutant median execs + median secs, across trials
    me = {m: statistics.median(v[0]) for m, v in by.items()}
    ms = {m: statistics.median(v[1]) for m, v in by.items()}
    return me, ms

EDGES = [10, 100, 1000, 10000]
BUCKET_LABELS = ["<10", "10-100", "100-1k", "1k-10k", ">10k"]
COLORS = ["#1a9850", "#a6d96a", "#fee08b", "#fdae61", "#d73027"]

def bucket(n):
    for i, e in enumerate(EDGES):
        if n < e: return i
    return len(EDGES)

labels, data, summary = [], [], []
for name, fn in ENGINES:
    by = load(fn)
    me, ms = medians(by)
    counts = [0] * 5
    for m, v in me.items():
        counts[bucket(v)] += 1
    n = sum(counts)
    labels.append(f"{name}  (n={n})")
    data.append(counts)
    evals = list(me.values()); times = list(ms.values())
    summary.append((name, n, statistics.median(evals), max(evals),
                    statistics.median(times), max(times)))

# ---- bucket chart (normalized per row) ----
fig, ax = plt.subplots(figsize=(11, 0.5 * len(labels) + 2))
y = range(len(labels)); left = [0.0] * len(labels)
totals = [sum(d) for d in data]
for b in range(5):
    vals = [100.0 * d[b] / t for d, t in zip(data, totals)]
    ax.barh(y, vals, left=left, color=COLORS[b], edgecolor="white", height=0.7)
    for i, (v, l, d) in enumerate(zip(vals, left, data)):
        if v >= 4:
            ax.text(l + v / 2, i, str(d[b]), va="center", ha="center", fontsize=8)
    left = [l + v for l, v in zip(left, vals)]
ax.set_yticks(list(y)); ax.set_yticklabels(labels, fontsize=10); ax.invert_yaxis()
ax.set_xlabel("% of 20 mutants by executions-to-find (tests+discards, per-mutant median of 5 trials; labels = mutant counts)")
ax.set_title("ETNA IFC (SSNI) workload — executions-to-find by strategy")
ax.set_xlim(0, 100)
handles = [mpatches.Patch(color=COLORS[i], label=BUCKET_LABELS[i]) for i in range(5)]
ax.legend(handles=handles, loc="upper center", bbox_to_anchor=(0.5, -0.18), fontsize=9, ncol=5)
plt.tight_layout()
out1 = os.path.join(FIG, "ifc_execs.png")
plt.savefig(out1, dpi=130, bbox_inches="tight"); print("saved", out1)

# ---- time chart (per-mutant median seconds, grouped) ----
fig, ax = plt.subplots(figsize=(11, 4))
import numpy as np
x = np.arange(20); w = 0.27
for k, (name, fn) in enumerate(ENGINES):
    _, ms = medians(load(fn))
    ys = [ms.get(m, 0) * 1000 for m in range(20)]   # ms
    ax.bar(x + (k - 1) * w, ys, w, label=name)
ax.set_xticks(x); ax.set_xticklabels([str(i) for i in range(20)], fontsize=7)
ax.set_xlabel("mutant"); ax.set_ylabel("time-to-find (ms, median of 5 trials)")
ax.set_title("ETNA IFC (SSNI) workload — time-to-find per mutant by strategy")
ax.legend(fontsize=9)
plt.tight_layout()
out2 = os.path.join(FIG, "ifc_time.png")
plt.savefig(out2, dpi=130, bbox_inches="tight"); print("saved", out2)

# ---- summary table ----
print("\n%-24s %6s %12s %10s %12s %10s" % ("strategy", "solved", "med execs", "max execs", "med time", "max time"))
for name, n, mev, xev, mt, xt in summary:
    print("%-24s %4d/20 %12.0f %10.0f %10.1fms %8.1fms" % (name, n, mev, xev, mt * 1000, xt * 1000))
