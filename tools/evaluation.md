# Expenses evaluation

Generated 17 November 2026 at 16:36.

## Extraction test

Folder: `eval_images` · model: `claude-haiku-5-5` · files: 20 · errors: 3

Overall field accuracy: **99.3%** · average 13.8 s per file · 87886 tokens total

| Field | Correct | Of | Accuracy |
|---|---|---|---|
| vendor | 17 | 17 | 100.0% |
| vatNumber | 17 | 17 | 100.0% |
| invoiceNumber | 16 | 17 | 94.1% |
| date | 17 | 17 | 100.0% |
| subtotal | 17 | 17 | 100.0% |
| vatAmount | 17 | 17 | 100.0% |
| total | 17 | 17 | 100.0% |
| currency | 17 | 17 | 100.0% |

### Mismatches

| File | Field | Expected | Actual |
|---|---|---|---|
| sei-000369-clean-p0.png | invoiceNumber | SIN-2023-000001 | placeholder |

### Errors

- sei-000001-clean-p0.png: Claude returned placeholder values instead of invoice data.
- sei-000062-clean-p0.png: Claude returned placeholder values instead of invoice data.
- sei-000063-clean-p0.png: Claude returned placeholder values instead of invoice data.

