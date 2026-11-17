# Backlog

Items noted during earlier phases. Done items are kept for reference.

## Done in the polish pass (2026-11-17)
- Day granularity readable: timeline uses a real date axis with automatic label thinning and a fixed domain for bounded periods.
- Hover on all three charts: timeline rule + tooltip, donut sector highlight with centre readout, vendor bar highlight with count.
- Generator: `tools/make_samples.py --count 300 --months 24 --out <dir>` for bulk data.
- Invoices table: click column headers to sort, search field, period filter in the toolbar.

## Open
- Import a bulk sample set and sanity-check chart performance with a few hundred rows.
- Try a real public dataset (see docs/datasets.md) for extraction accuracy.
