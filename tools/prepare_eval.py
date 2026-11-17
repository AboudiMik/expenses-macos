#!/usr/bin/env python3
"""Build tools/eval_images from a labelled invoice dataset.

Supported input: a folder of Parquet shards from Bayanat-Labs/saudi-einvoice-synth
(the `pages` config). Picks clean simplified tax invoices (thermal receipts), writes
their PNGs and a ground_truth.json using this app's field names. If no labels can be
found, copies up to 10 images and writes no ground truth.

Usage: tools/.venv/bin/python tools/prepare_eval.py tools/dataset/bayanat [--count 20]
"""
import argparse
import glob
import json
import os
import shutil
from pathlib import Path

OUT_DIR = Path(__file__).parent / "eval_images"
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".webp")


def from_parquet(src: Path, count: int):
    import pyarrow.parquet as pq

    columns = ["id", "record_id", "doc_type", "variant", "layout", "numeral_system", "image", "canonical"]
    picked = []
    for shard in sorted(glob.glob(str(src / "**" / "*.parquet"), recursive=True)):
        for row in pq.read_table(shard, columns=columns).to_pylist():
            if row["doc_type"] != "simplified_tax_invoice" or row["variant"] != "clean":
                continue
            picked.append(row)
            if len(picked) >= count:
                return picked
    return picked


def ground_truth(row):
    c = json.loads(row["canonical"])
    seller, totals = c["seller"], c["totals"]
    names = [seller.get(k) for k in ("trade_name_en", "trade_name_ar", "name_en", "name_ar")]
    return {
        "vendor": [n for n in names if n],          # any of these counts as correct
        "vatNumber": str(seller.get("vat") or ""),
        "invoiceNumber": str(c.get("invoice_number") or ""),
        "date": c.get("issue_date"),
        "subtotal": float(totals["tax_exclusive"]),
        "vatAmount": float(totals["tax_total"]),
        "total": float(totals["tax_inclusive"]),
        "currency": c.get("currency", "SAR"),
        "source": {"dataset": "Bayanat-Labs/saudi-einvoice-synth", "record": row["record_id"],
                   "layout": row["layout"], "numerals": row["numeral_system"], "license": "CC BY 4.0"},
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset", type=Path)
    parser.add_argument("--count", type=int, default=20)
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.iterdir():
        old.unlink()

    shards = glob.glob(str(args.dataset / "**" / "*.parquet"), recursive=True)
    if shards:
        rows = from_parquet(args.dataset, args.count)
        truth = {}
        for row in rows:
            name = f"{row['id']}.png"
            (OUT_DIR / name).write_bytes(row["image"]["bytes"])
            truth[name] = ground_truth(row)
        (OUT_DIR / "ground_truth.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2))
        print(f"{len(rows)} labelled receipts written to {OUT_DIR} with ground_truth.json")
        if len(rows) < args.count:
            print(f"Only {len(rows)} clean simplified invoices found; download more shards for {args.count}.")
        return

    images = [p for p in sorted(args.dataset.rglob("*")) if p.suffix.lower() in IMAGE_EXT][:10]
    for p in images:
        shutil.copy(p, OUT_DIR / p.name)
    print(f"No labels found. Copied {len(images)} images to {OUT_DIR} without ground truth.")


if __name__ == "__main__":
    main()
