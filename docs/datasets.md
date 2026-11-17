# Public invoice and receipt datasets

Researched 2026-11-17 for extraction-accuracy and bulk chart testing. Nothing downloaded yet.

| Dataset | Contents | Amounts annotated | Licence | Size | Fit |
|---|---|---|---|---|---|
| [Bayanat-Labs/saudi-einvoice-synth](https://huggingface.co/datasets/Bayanat-Labs/saudi-einvoice-synth) | Synthetic Saudi ZATCA documents; 8,700 simplified tax invoices as 80/58 mm thermal receipts, PNG clean + degraded, UBL XML, QR, Arabic + English | Yes, every field incl. 15-digit VAT number, subtotal, VAT, total, line items | CC BY 4.0, commercial OK | 36.5 GB (streamable; pull the simplified subset only) | Closest match to our domain |
| [SROIE (ICDAR 2019)](https://huggingface.co/datasets/darentang/sroie) | ~1,000 real scanned Malaysian receipts, JPG + labels | Company, date, total; no VAT or line items | CC BY 4.0 on mirrors | ~1 GB | Standard real-receipt benchmark |
| [CORD](https://huggingface.co/datasets/naver-clova-ix/cord-v2) | 1,000 real Indonesian receipt photos | Line items, subtotal, tax, total | CC BY 4.0 | ~1-2 GB | Best real line-item ground truth, wrong currency |
| [DocILE](https://docile.rossum.ai) | 6,680 real annotated US invoices as PDF | Total, tax, vendor, line items | CC BY 4.0, gated by access form | several GB | Only real-PDF set with tax and line items |
| [katanaml-org/invoices-donut-data-v1](https://huggingface.co/datasets/katanaml-org/invoices-donut-data-v1) | 501 real electronic invoices, images + JSON | Header, line items, totals, tax | MIT | 198 MB | Quick smoke tests |
| [albertobarnabo/synthetic-receipts-ocr](https://huggingface.co/datasets/albertobarnabo/synthetic-receipts-ocr) | 32,000 synthetic receipts, clean + photo-degraded, 5 languages | Full, arithmetic verified | Apache-2.0 | 4 GB | Bulk testing, VAT maths checks |
| [FATURA v2](https://zenodo.org/records/10371464) | 20,000 synthetic invoice JPGs, 50 layouts | Partial (bounding boxes with text) | CC BY 4.0 | 690 MB | Layout robustness |
| [Shubhal829/high-quality-invoice-images-for-ocr](https://huggingface.co/datasets/Shubhal829/high-quality-invoice-images-for-ocr) | 8,181 synthetic invoice JPGs, 1,489 with JSON | Yes for the annotated subset | ODbL | 2.4 GB | A few hundred records for charts |

Arabic / Gulf: Bayanat is the only ZATCA-specific set. [CORU / ReceiptSense](https://huggingface.co/datasets/abdoelsayed/CORU) has 20,000 real Arabic/English receipts (mostly Egyptian, EGP, CC BY 4.0, 15.9 GB), useful for Arabic OCR robustness only. ZATCA publishes no sample corpus, only guideline PDFs.

Not recommended: RVL-CDIP invoices (no amounts, 1990s scans), FUNSD (forms), AMuRD (text lines only, non-commercial), Nexdata (paid).

## Recommendation

- Extraction accuracy: Bayanat simplified-invoice subset first, then SROIE and katanaml as real-world sanity checks.
- Bulk chart testing: albertobarnabo synthetic receipts (stream a few hundred) or the Bayanat subset for in-currency SAR data. Extending `tools/make_samples.py` to a few hundred invoices is the zero-download alternative.
