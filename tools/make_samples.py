#!/usr/bin/env python3
"""Generate 15 sample Saudi simplified tax invoice PDFs into tools/samples/.

Vendors, VAT numbers and amounts are fictional. Dates spread across the
last 14 months; categories rotate through the app's eight categories.
Run with a fixed seed so the output is reproducible.
"""
import argparse
import random
from datetime import date, timedelta
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

OUT_DIR = Path(__file__).parent / "samples"
COUNT = 15
VAT_RATE = 0.15
SEED = 2026

CATEGORIES = ["Food", "Transport", "Utilities", "Office",
              "Software", "Travel", "Health", "Other"]

# category -> (vendors, line items with (description, min price, max price))
CATALOG = {
    "Food": (
        ["Al Baik Restaurant", "Herfy Food Services", "Kudu Riyadh",
         "Danube Supermarket"],
        [("Chicken meal", 18, 45), ("Fresh juice", 8, 15), ("Rice box", 12, 30),
         ("Mineral water 1.5L", 2, 5), ("Grilled kebab plate", 35, 70),
         ("Arabic coffee", 10, 20), ("Dates 1kg", 25, 60)],
    ),
    "Transport": (
        ["Careem Networks", "Uber Saudi", "Petromin Express",
         "Saudi Public Transport Co"],
        [("City ride", 15, 60), ("Airport transfer", 80, 150),
         ("Fuel 91 octane", 50, 200), ("Parking fee", 10, 40),
         ("Car wash", 30, 60), ("Bus pass", 20, 100)],
    ),
    "Utilities": (
        ["Saudi Electricity Company", "National Water Company", "STC",
         "Mobily"],
        [("Electricity consumption", 150, 900), ("Water consumption", 40, 250),
         ("Fiber internet monthly", 199, 399), ("Mobile plan", 69, 199),
         ("Service fee", 10, 30)],
    ),
    "Office": (
        ["Jarir Bookstore", "Maktabat Al Obeikan", "Saco Stores",
         "Office Hub Trading"],
        [("A4 paper ream", 18, 30), ("Toner cartridge", 180, 350),
         ("Ballpoint pens pack", 12, 25), ("Desk organizer", 45, 90),
         ("Whiteboard markers", 15, 35), ("Stapler", 20, 45)],
    ),
    "Software": (
        ["Al Moammar Information Systems", "Elm Company", "STC Solutions",
         "Sahara Net"],
        [("Cloud hosting monthly", 150, 600), ("Software licence seat", 99, 450),
         ("Domain renewal", 50, 120), ("SSL certificate", 120, 300),
         ("Support plan", 200, 500)],
    ),
    "Travel": (
        ["Saudia Airlines", "flynas", "Al Tayyar Travel", "Hilton Riyadh Hotel"],
        [("Domestic flight", 350, 900), ("Hotel night", 400, 1200),
         ("Baggage fee", 80, 150), ("Travel insurance", 60, 150),
         ("Airport lounge", 120, 200)],
    ),
    "Health": (
        ["Nahdi Pharmacy", "Al Dawaa Pharmacy", "Dr. Sulaiman Al Habib Clinic",
         "Dallah Hospital"],
        [("Consultation fee", 150, 400), ("Paracetamol 500mg", 8, 20),
         ("Vitamin D supplement", 35, 80), ("Lab test", 120, 450),
         ("Face masks box", 15, 30), ("Blood pressure check", 50, 100)],
    ),
    "Other": (
        ["Extra Stores", "IKEA Saudi Arabia", "Al Othaim Markets", "Noon KSA"],
        [("Household item", 20, 150), ("Gift voucher", 50, 200),
         ("Cleaning supplies", 15, 60), ("Phone accessory", 25, 120),
         ("Laundry service", 30, 90)],
    ),
}

CITIES = ["Riyadh", "Jeddah", "Dammam", "Khobar", "Makkah", "Madinah"]


def vat_number(rng):
    # Saudi VAT numbers are 15 digits, start with 3 and end with 3.
    middle = "".join(str(rng.randint(0, 9)) for _ in range(13))
    return f"3{middle}3"


def spread_dates(rng, count, months=14):
    today = date.today()
    start = today - timedelta(days=months * 30)
    span = (today - start).days
    step = span / count
    return sorted(start + timedelta(days=int(i * step + rng.uniform(0, step)))
                  for i in range(count))


_used_numbers = set()


def unique_invoice_number(rng, year):
    while True:
        number = f"INV-{year}-{rng.randint(1000, 9999)}"
        if number not in _used_numbers:
            _used_numbers.add(number)
            return number


def build_invoice(rng, index, inv_date):
    category = CATEGORIES[index % len(CATEGORIES)]
    vendors, items = CATALOG[category]
    vendor = rng.choice(vendors)
    chosen = rng.sample(items, k=rng.randint(2, 5))
    lines = []
    for desc, lo, hi in chosen:
        qty = rng.randint(1, 4)
        unit = round(rng.uniform(lo, hi), 2)
        lines.append((desc, qty, unit, round(qty * unit, 2)))
    subtotal = round(sum(l[3] for l in lines), 2)
    vat = round(subtotal * VAT_RATE, 2)
    return {
        "category": category,
        "vendor": vendor,
        "city": rng.choice(CITIES),
        "vat_number": vat_number(rng),
        "invoice_number": unique_invoice_number(rng, inv_date.year),
        "date": inv_date,
        "lines": lines,
        "subtotal": subtotal,
        "vat": vat,
        "total": round(subtotal + vat, 2),
    }


def sar(amount):
    return f"{amount:,.2f} SAR"


def draw_invoice(path, inv):
    c = canvas.Canvas(str(path), pagesize=A4, invariant=1)  # fixed timestamps: reruns are byte-identical
    w, h = A4
    x0, y = 20 * mm, h - 25 * mm

    c.setFont("Helvetica-Bold", 16)
    c.drawString(x0, y, "Simplified Tax Invoice")
    c.setFont("Helvetica", 9)
    c.drawRightString(w - x0, y, "Kingdom of Saudi Arabia")
    y -= 12 * mm

    c.setFont("Helvetica-Bold", 12)
    c.drawString(x0, y, inv["vendor"])
    y -= 6 * mm
    c.setFont("Helvetica", 10)
    c.drawString(x0, y, f"{inv['city']}, Saudi Arabia")
    y -= 6 * mm
    c.drawString(x0, y, f"VAT Number: {inv['vat_number']}")
    y -= 10 * mm

    c.drawString(x0, y, f"Invoice Number: {inv['invoice_number']}")
    c.drawRightString(w - x0, y, f"Date: {inv['date'].isoformat()}")
    y -= 6 * mm
    c.drawString(x0, y, f"Category: {inv['category']}")
    y -= 10 * mm

    cols = [x0, x0 + 90 * mm, x0 + 115 * mm, x0 + 145 * mm]
    c.setFillColor(colors.HexColor("#EEEEEE"))
    c.rect(x0, y - 2 * mm, w - 2 * x0, 7 * mm, fill=1, stroke=0)
    c.setFillColor(colors.black)
    c.setFont("Helvetica-Bold", 10)
    for label, x in zip(["Description", "Qty", "Unit Price", "Amount"], cols):
        c.drawString(x, y, label)
    y -= 8 * mm

    c.setFont("Helvetica", 10)
    for desc, qty, unit, amount in inv["lines"]:
        c.drawString(cols[0], y, desc)
        c.drawString(cols[1], y, str(qty))
        c.drawString(cols[2], y, f"{unit:,.2f}")
        c.drawRightString(w - x0, y, f"{amount:,.2f}")
        y -= 6 * mm

    y -= 4 * mm
    c.line(x0 + 100 * mm, y, w - x0, y)
    y -= 7 * mm
    for label, value in [("Subtotal (excl. VAT)", inv["subtotal"]),
                         ("VAT 15%", inv["vat"])]:
        c.drawString(x0 + 100 * mm, y, label)
        c.drawRightString(w - x0, y, sar(value))
        y -= 6 * mm
    c.setFont("Helvetica-Bold", 11)
    c.drawString(x0 + 100 * mm, y, "Total (incl. VAT)")
    c.drawRightString(w - x0, y, sar(inv["total"]))

    c.setFont("Helvetica-Oblique", 8)
    c.drawString(x0, 20 * mm, "Fictional sample invoice generated for testing. Not a real transaction.")
    c.showPage()
    c.save()


def main():
    parser = argparse.ArgumentParser(description="Generate sample Saudi simplified tax invoices.")
    parser.add_argument("--count", type=int, default=COUNT, help="number of invoices (default 15)")
    parser.add_argument("--months", type=int, default=14, help="spread dates over the last N months")
    parser.add_argument("--out", type=Path, default=OUT_DIR, help="output folder (default tools/samples)")
    parser.add_argument("--seed", type=int, default=SEED)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    args.out.mkdir(parents=True, exist_ok=True)
    for old in args.out.glob("*.pdf"):
        old.unlink()
    width = max(2, len(str(args.count)))
    dates = spread_dates(rng, args.count, months=args.months)
    for i, inv_date in enumerate(dates):
        inv = build_invoice(rng, i, inv_date)
        slug = inv["vendor"].lower().replace(" ", "_").replace(".", "")
        path = args.out / f"{i + 1:0{width}d}_{inv_date.isoformat()}_{slug}.pdf"
        draw_invoice(path, inv)
        print(f"{path.name}  {inv['category']:<10} {sar(inv['total'])}")
    print(f"\n{args.count} invoices written to {args.out}")


if __name__ == "__main__":
    main()
