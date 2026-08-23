#!/usr/bin/env python3
"""Aggregate Ruby benchmark results and build a standalone report."""

import argparse
import json
import math
import re
import statistics
from collections import defaultdict
from pathlib import Path


def dig(value, *keys, default=0):
    for key in keys:
        if not isinstance(value, dict):
            return default
        value = value.get(key)
    return default if value is None else value


def numbers(values):
    return [float(value) for value in values if isinstance(value, (int, float)) and math.isfinite(value)]


def mean(values):
    values = numbers(values)
    return statistics.mean(values) if values else 0.0


def stdev(values):
    values = numbers(values)
    return statistics.stdev(values) if len(values) > 1 else 0.0


def median(values):
    values = numbers(values)
    return statistics.median(values) if values else 0.0


def parse_version(name):
    match = re.match(r"ruby(\d+\.\d+)-([a-z]+)-(.+)", name)
    return (match.group(1), match.group(2), match.group(3)) if match else ("0.0", "unknown", name)


def load_runs(root):
    runs = []
    for path in root.glob("ruby*/profile-*/*/fork*/result.json"):
        try:
            data = json.loads(path.read_text())
        except Exception as error:
            print(f"warning: skipping {path}: {error}")
            continue
        line, kind, version = parse_version(path.parents[3].name)
        runs.append({
            "path": str(path.relative_to(root)),
            "line": line,
            "kind": kind,
            "version": version,
            "version_label": f"Ruby {line}" + (f" ({kind})" if kind != "latest" else ""),
            "profile": path.parents[2].name.removeprefix("profile-"),
            "scenario": data.get("scenario", path.parents[1].name),
            "data": data,
        })
    return runs


def summarize(runs):
    grouped = defaultdict(list)
    for run in runs:
        grouped[(run["line"], run["kind"], run["version"], run["profile"], run["scenario"])].append(run)
    groups = []
    for (line, kind, version, profile, scenario), items in grouped.items():
        results = [item["data"]["results"] for item in items]
        sample_count = max((len(result.get("timeseries", [])) for result in results), default=0)
        series = []
        for index in range(sample_count):
            samples = [result["timeseries"][index] for result in results if index < len(result.get("timeseries", []))]
            series.append({
                "t_s": median([sample.get("t_s") for sample in samples]),
                "cpu_pct": median([sample.get("process_pct_all") for sample in samples]),
                "rss_mib": median([sample.get("process_rss_bytes") for sample in samples]) / 1048576,
                "heap_live_slots": median([sample.get("heap_live_slots") for sample in samples]),
            })
        throughput = [result["throughput_ops_s"] for result in results]
        groups.append({
            "line": line,
            "kind": kind,
            "version": version,
            "version_label": f"Ruby {line}" + (f" ({kind})" if kind != "latest" else ""),
            "profile": profile,
            "scenario": scenario,
            "forks": len(items),
            "throughput_mean": mean(throughput),
            "throughput_stdev": stdev(throughput),
            "latency_mean_us": mean([dig(result, "latency", "mean_us") for result in results]),
            "latency_p95_us": mean([dig(result, "latency", "p95_us") for result in results]),
            "latency_p99_us": mean([dig(result, "latency", "p99_us") for result in results]),
            "gc_collections_mean": mean([dig(result, "gc", "collections") for result in results]),
            "gc_pause_ms_mean": mean([dig(result, "gc", "pause_total_ms") for result in results]),
            "cpu_pct_mean": mean([dig(result, "cpu", "process_pct_all_cores", "mean") for result in results]),
            "rss_mib_mean": mean([dig(result, "memory", "process_rss_bytes", "mean") for result in results]) / 1048576,
            "heap_live_slots_mean": mean([dig(result, "memory", "heap_live_slots", "mean") for result in results]),
            "timeseries": series,
        })
    groups.sort(key=lambda group: (group["scenario"], group["profile"], tuple(map(int, group["line"].split("."))), group["kind"]))
    return {"schema_version": 1, "run_count": len(runs), "groups": groups}


def markdown(summary):
    lines = [
        "# Ruby Version Benchmark Report", "",
        "Means across isolated process repeats. Higher throughput is better.", "",
        "| Scenario | Profile | Ruby | Patch | Repeats | M ops/s | p95 us | GC count | CPU % | RSS MiB |",
        "|:--|:--|:--|:--|--:|--:|--:|--:|--:|--:|",
    ]
    for group in summary["groups"]:
        lines.append(
            f"| {group['scenario']} | {group['profile']} | {group['version_label']} | {group['version']} | "
            f"{group['forks']} | {group['throughput_mean'] / 1e6:.3f} | {group['latency_p95_us']:.2f} | "
            f"{group['gc_collections_mean']:.1f} | {group['cpu_pct_mean']:.2f} | {group['rss_mib_mean']:.1f} |"
        )
    lines += ["", "Open `dashboard.html` for interactive charts.", ""]
    return "\n".join(lines)


HTML = r'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Ruby Version Benchmark</title><style>
body{margin:0;background:#130d17;color:#f5eaf6;font:14px system-ui}main{max-width:1300px;margin:auto;padding:38px 22px}h1{font-size:42px;margin-bottom:8px}p{color:#bea9c2}.panel{background:#211526;border:1px solid #493250;border-radius:14px;padding:20px;margin-top:22px}select{background:#160f1a;color:#fff;border:1px solid #67496e;padding:8px;margin-right:8px}canvas{width:100%;height:420px;margin-top:18px}table{width:100%;border-collapse:collapse;margin-top:14px}th,td{padding:9px;border-bottom:1px solid #493250;text-align:right}th:first-child,td:first-child{text-align:left}
</style></head><body><main><h1>Ruby runtime evolution</h1><p>Same Ruby source, official images, isolated repeats.</p><div class="panel"><select id="scenario"></select><select id="profile"></select><canvas id="chart"></canvas></div><div class="panel"><table><thead><tr><th>Ruby</th><th>M ops/s</th><th>p95 us</th><th>GC count</th><th>RSS MiB</th></tr></thead><tbody id="rows"></tbody></table></div></main><script>
const data=__DATA__,groups=data.groups,$=id=>document.getElementById(id),uniq=a=>[...new Set(a)];function options(id,values){$(id).innerHTML=values.map(v=>`<option>${v}</option>`).join('')}options('scenario',uniq(groups.map(x=>x.scenario)));options('profile',uniq(groups.map(x=>x.profile)));function draw(){const xs=groups.filter(x=>x.scenario===$('scenario').value&&x.profile===$('profile').value),c=$('chart'),d=devicePixelRatio||1,w=c.clientWidth,h=c.clientHeight;c.width=w*d;c.height=h*d;const g=c.getContext('2d');g.scale(d,d);g.clearRect(0,0,w,h);const L=60,B=50,T=25,R=20,max=Math.max(...xs.map(x=>x.throughput_mean/1e6),1)*1.12;g.strokeStyle='#553c5d';g.fillStyle='#bea9c2';g.font='12px system-ui';for(let i=0;i<=5;i++){const y=T+(h-T-B)*i/5;g.beginPath();g.moveTo(L,y);g.lineTo(w-R,y);g.stroke();g.fillText((max*(1-i/5)).toFixed(2),8,y+4)}const bw=(w-L-R)/Math.max(xs.length,1)*.62;xs.forEach((x,i)=>{const value=x.throughput_mean/1e6,bh=(h-T-B)*value/max,left=L+(i+.2)*(w-L-R)/xs.length;g.fillStyle='#e75bce';g.fillRect(left,h-B-bh,bw,bh);g.fillStyle='#f3dff1';g.fillText(x.version_label,left,h-B+18)});$('rows').innerHTML=xs.map(x=>`<tr><td>${x.version_label} ${x.profile}</td><td>${(x.throughput_mean/1e6).toFixed(3)}</td><td>${x.latency_p95_us.toFixed(2)}</td><td>${x.gc_collections_mean.toFixed(1)}</td><td>${x.rss_mib_mean.toFixed(1)}</td></tr>`).join('')}scenario.onchange=draw;profile.onchange=draw;addEventListener('resize',draw);draw();
</script></body></html>'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results_dir", type=Path)
    args = parser.parse_args()
    summary = summarize(load_runs(args.results_dir))
    args.results_dir.mkdir(parents=True, exist_ok=True)
    (args.results_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    (args.results_dir / "report.md").write_text(markdown(summary))
    payload = json.dumps(summary, separators=(",", ":")).replace("</", "<\\/")
    (args.results_dir / "dashboard.html").write_text(HTML.replace("__DATA__", payload))
    print(args.results_dir / "dashboard.html")


if __name__ == "__main__":
    main()
