#!/usr/bin/env python3
"""Daily 电池方案 index for 蔚来 / 乐道 / firefly萤火虫 used-car listings on dongchedi.

Pages through every nationwide listing of those brands, reads each listing's detail
(sh_car_desc = seller description), classifies 租电 / 买断 / 未注明 with exactly the same
rules as BatteryPlan.classify in the app, and writes a compact JSON:
  {generated_at, rules_version, brands, counts, items: {sku_id: "rent"|"buy"|"unknown"}}
Listings whose detail could not be read (rate limited / delisted) are left out, unless the
previous index already knew them (then the previous value is kept, marked in stats).
"""
import argparse, concurrent.futures as cf, datetime, gzip, json, os, random, re, sys, threading, time
import urllib.parse, urllib.request

RULES_VERSION = 1
BRANDS = {112: "蔚来", 918: "乐道", 10363: "萤火虫"}
BASE = "https://www.dongchedi.com"
Q = "aid=1839&app_name=auto_web_pc"
H = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
     "Referer": "https://www.dongchedi.com/usedcar"}

# --- must stay identical to BatteryPlan in DCDUsedCar/API.swift ---
NEG_RENT = re.compile(r"非租电|不租电|无需租电", re.I)
RENT = re.compile(r"租电|电池\s*租(?:用|赁|电)|租(?:用|赁)\s*电池|BaaS|电池\s*月租", re.I)
BUY = re.compile(r"非租电|不租电|无需租电|电池\s*(?:已)?\s*买断|买断\s*(?:版|电池)|\d{2,3}\s*(?:度|°|kwh)\s*(?:电池)?\s*买断|电池\s*(?:已)?\s*(?:购买|买了)|车电一体", re.I)

def classify(text):
    b = bool(BUY.search(text))
    r = bool(RENT.search(NEG_RENT.sub("", text)))
    if r == b:
        return "unknown"
    return "rent" if r else "buy"

stats_lock = threading.Lock()
stats = {"requests": 0, "retries": 0}

def fetch(req, tries=9):
    for a in range(tries):
        with stats_lock:
            stats["requests"] += 1
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                j = json.load(r)
            if isinstance(j, dict) and j.get("status", 0) in (0, None):
                return j
        except Exception:
            pass
        with stats_lock:
            stats["retries"] += 1
        time.sleep(min(0.4 * (1.7 ** a), 12) * random.uniform(0.8, 1.2))
    return None

def sku_list(form):
    form = {**form}
    req = urllib.request.Request(f"{BASE}/motor/pc/sh/sh_sku_list?{Q}", data=urllib.parse.urlencode(form).encode(),
                                 headers={**H, "Content-Type": "application/x-www-form-urlencoded"})
    j = fetch(req)
    return (j or {}).get("data")

def major(sku, city):
    u = f"{BASE}/motor/pc/sh/detail/major?{Q}&" + urllib.parse.urlencode({"sku_id": sku, "city_name": city or "全国"})
    return fetch(urllib.request.Request(u, headers=H))

def page_all(base_form, seen, label):
    """Page with the max page size (80); returns total reported by the API."""
    total, page = None, 1
    while page <= 200:
        d = sku_list({**base_form, "page": page, "limit": 80})
        if d is None:
            print(f"  {label}: page {page} failed", flush=True); break
        total = d.get("total", total)
        lst = d.get("search_sh_sku_info_list") or []
        for x in lst:
            sid = str(x.get("sku_id"))
            seen.setdefault(sid, {"brand": x.get("brand_id"), "series": x.get("series_id"),
                                  "city": x.get("car_source_city_name") or x.get("brand_source_city_name") or "全国"})
        if not lst or not d.get("has_more"):
            break
        page += 1
        time.sleep(0.15)
    return total or 0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="out")
    ap.add_argument("--prev", default="")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0, help="debug: only classify N listings")
    a = ap.parse_args()
    t0 = time.time()
    prev = {}
    if a.prev and os.path.exists(a.prev):
        try: prev = json.load(open(a.prev)).get("items", {})
        except Exception: prev = {}

    listings, totals = {}, {}
    for bid, name in BRANDS.items():
        seen = {}
        total = page_all({"sh_city_name": "全国", "brand": bid}, seen, name)
        if len(seen) < total:   # paging limit hid some: split by series, then by city
            for s in sorted({v["series"] for v in seen.values() if v["series"]}):
                page_all({"sh_city_name": "全国", "brand": bid, "series_ids": s}, seen, f"{name}/series {s}")
        if len(seen) < total:
            for c in sorted({v["city"] for v in seen.values() if v["city"]}):
                page_all({"sh_city_name": c, "brand": bid}, seen, f"{name}/{c}")
        totals[bid] = {"name": name, "api_total": total, "listed": len(seen)}
        print(f"{name}: api total {total}, listed {len(seen)}", flush=True)
        for k, v in seen.items():
            v["brand"] = bid
            listings[k] = v

    keys = list(listings)[: a.limit or None]
    items, failed, kept = {}, 0, 0
    def work(k):
        j = major(k, listings[k]["city"])
        d = (j or {}).get("data") or {}
        if not d.get("car_info"):
            return k, None
        return k, classify((d.get("title") or "") + "\n" + (d.get("sh_car_desc") or ""))
    with cf.ThreadPoolExecutor(a.workers) as ex:
        for i, (k, p) in enumerate(ex.map(work, keys), 1):
            if p is None:
                failed += 1
                if k in prev: items[k] = prev[k]; kept += 1
            else:
                items[k] = p
            if i % 200 == 0:
                print(f"  details {i}/{len(keys)} ({int(time.time() - t0)}s, failed {failed})", flush=True)

    counts = {"rent": 0, "buy": 0, "unknown": 0}
    per_brand = {}
    for k, p in items.items():
        counts[p] += 1
        b = per_brand.setdefault(str(listings[k]["brand"]), {"rent": 0, "buy": 0, "unknown": 0})
        b[p] += 1
    tz = datetime.timezone(datetime.timedelta(hours=8))
    out = {"generated_at": datetime.datetime.now(tz).isoformat(timespec="seconds"), "rules_version": RULES_VERSION,
           "brands": {str(b): {**totals[b], **per_brand.get(str(b), {})} for b in totals},
           "counts": counts,
           "stats": {"listings": len(listings), "classified": len(items), "failed": failed, "kept_from_previous": kept,
                     "requests": stats["requests"], "retries": stats["retries"], "seconds": int(time.time() - t0)},
           "items": items}
    os.makedirs(a.out, exist_ok=True)
    raw = json.dumps(out, ensure_ascii=False, separators=(",", ":")).encode()
    open(os.path.join(a.out, "battery-index.json"), "wb").write(raw)
    open(os.path.join(a.out, "battery-index.json.gz"), "wb").write(gzip.compress(raw, 9))
    summary = {k: v for k, v in out.items() if k != "items"}
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    print(f"size {len(raw)} B, gzip {len(gzip.compress(raw, 9))} B")
    if len(keys) and len(items) < 0.8 * len(keys):
        print("too many failures — refusing to publish", file=sys.stderr); sys.exit(1)

if __name__ == "__main__":
    main()
