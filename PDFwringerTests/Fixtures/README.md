# PDF Test Fixtures

Drop real-world PDF files into this directory (or subdirectories) to include them in the automated test suite. Tests auto-discover all `.pdf` files recursively.

## Directory Structure

```
Fixtures/
├── small/        ← PDFs under ~100 KB (business cards, receipts, 1-pagers)
├── large/        ← PDFs over ~5 MB (photo books, catalogs, presentations)
├── scanned/      ← Scanned documents (image-heavy, often large DPI)
├── encoded/      ← Unusual encodings, JBIG2, encrypted (no password), CJK fonts
├── multipage/    ← Documents with 50+ pages
├── rotated/      ← PDFs with pre-rotated pages (90°, 180°, 270°)
├── mixed/        ← Mixed page sizes, orientations, or content types
└── *.pdf         ← Any PDF at root level is also tested
```

## What Gets Tested

Every PDF dropped here is automatically run through:

1. **Open & validate** — Can PDFKit and CGPDFDocument open it? Page count > 0?
2. **Compress (lossless)** — Output is valid, same page count
3. **Compress (rasterize)** — Output is valid, same page count, size differs from source
4. **Rotate 90°** — Output is valid, same page count
5. **Split** — Output files have correct combined page count
6. **Crop** — Output is valid, page dimensions reduced
7. **Color adjust** — Output is valid, same page count
8. **Metadata read/write** — Can read attributes, write without corruption
9. **Concatenate** — Two copies merged, output has 2× page count

## Naming Convention

No naming convention required — just drop PDFs. But descriptive names help when a test fails:
- `invoice_1page_50kb.pdf`
- `photo_book_200pages_45mb.pdf`
- `scanned_receipt_300dpi.pdf`
- `japanese_vertical_text.pdf`

## Important Notes

- **Do NOT commit sensitive documents.** The `Fixtures/` directory is gitignored.
- Password-protected PDFs will be tested for graceful rejection (not processing).
- Corrupt/invalid PDFs will be tested for graceful error handling.
- Tests are skipped (not failed) if the Fixtures directory is empty.
