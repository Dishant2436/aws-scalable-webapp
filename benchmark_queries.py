"""Measures REAL latency so the numbers on your resume are defensible.
Run once BEFORE db/indexes.sql and once AFTER; compare the p50/p95 output.
  python benchmarks/benchmark_queries.py --label baseline
  mysql < db/indexes.sql
  python benchmarks/benchmark_queries.py --label indexed
Also compares pooled vs non-pooled connections."""
import argparse, os, random, statistics, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))
from sqlalchemy import text
from db import build_engine

def run(engine, n):
    lat = []
    for _ in range(n):
        cid = random.randint(1, 5000)
        t = time.perf_counter()
        with engine.connect() as c:
            c.execute(text("SELECT id,total FROM orders WHERE customer_id=:c ORDER BY created_at DESC LIMIT 50"), {"c": cid}).all()
        lat.append((time.perf_counter() - t) * 1000)
    lat.sort()
    return statistics.mean(lat), lat[len(lat)//2], lat[int(len(lat)*0.95)]

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--label", default="run"); ap.add_argument("-n", type=int, default=500)
    a = ap.parse_args()
    for name, pooled in (("pooled", True), ("no-pool", False)):
        mean, p50, p95 = run(build_engine(pooled), a.n)
        print(f"[{a.label}] {name:8s} mean={mean:7.2f}ms p50={p50:7.2f}ms p95={p95:7.2f}ms")
