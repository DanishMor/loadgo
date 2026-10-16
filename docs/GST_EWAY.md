# GST invoice and e-way bill (G14)

What the app does today, what it checks, and what waits for a paid GSP (GST Suvidha Provider).

## The invoice PDF (lib/core/documents/invoice_pdf.dart)

Fields now printed: invoice number (gapless series per driver and financial year), date, seller name, seller GSTIN and its **state**, buyer name and GSTIN, trip (from, to, cargo, vehicle, LR), **HSN / SAC** (996511, goods transport by road), **place of supply**, **reverse charge**, e-way bill number, validity and distance, taxable value, the tax lines, total and total in words.

- **Place of supply**: the state of the buyer's GSTIN; if there is none, the state of the drop city; if that is unknown too, "-".
- **Tax lines**: seller and place of supply in the same state give CGST + SGST; different states give **one IGST line** (the sum of the two halves). When a state cannot be found the invoice keeps the older CGST + SGST view. The stored amounts do not change: IGST is only the sum.
- **Reverse charge** is printed as "No". Whether goods transport agency (GTA) services are under reverse charge depends on the rate chosen and on who the recipient is. **Ask the CA** (docs/LEGAL_QUESTIONS.md) and, if needed, make this a setting per driver.

## E-way bill rules (lib/core/gst/gst_rules.dart)

Plain functions, no network, tested: state of a GSTIN, supply kind (intra or inter state), 12-digit number, vehicle number, the value threshold, the validity from the distance (one day for each 200 km or part, 20 km for over-dimensional cargo; ends at the end of the last day), and a list of request problems. **The threshold (50,000 rupees) and the validity rules are the usual ones and change from time to time; confirm them with the CA and the GST portal before relying on them.**

## The GSP adapter (lib/core/adapters/eway_adapter.dart)

`EwayBillProvider.generate(request)`: `NoEwayBillProvider` (default, "not configured"), `FakeEwayBillProvider` (tests and demos), `GspEwayBillProvider` (skeleton calling a server function `ewayGenerate` that is **not written** until a GSP is chosen). All of them check the request first and name what is wrong.

Today the person makes the e-way bill on the GST portal and records the number and the date in the invoice card (the app checks the 12 digits and shows the expiry warning). Nothing is filed by the app.

## Choosing a GSP (for the owner)

Ask: price per e-way bill and per month, API for generate / update vehicle (Part B) / cancel, sandbox, uptime, data location, who holds the GST portal credentials (we should never store the taxpayer's portal password; use the GSP's authorised access), invoice IRN / e-invoice support if the turnover needs it, and a data processing agreement. Then add the server function with the key as a Firebase secret and a flag, copying the pattern of `functions/src/kyc.js`.
