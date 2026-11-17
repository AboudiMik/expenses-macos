# Backlog

Items noted during earlier phases, to be picked up in phase 5 (polishing) unless pulled forward.

## Dashboard
- Day granularity: bar labels are unreadable with sparse data. Options: date axis with
  thinned labels, or fill empty days with zero bars so the spacing is even.
- Hover tooltip on all three charts showing the exact value (ChartOverlay + chartXSelection).
- Test the charts against a larger dataset (public invoice/receipt dataset, or extend
  tools/make_samples.py to generate hundreds of invoices).

## Invoices
- Sort the table by any column (date, vendor, total, category) via Table sortOrder.
- Search and date-range filter in the toolbar.
