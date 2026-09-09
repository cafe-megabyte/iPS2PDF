# PDF-information test fixtures

These small PDFs contain synthetic test text only. They are not user documents.
Generate them with `python3 BuildSupport/Scripts/generate_pdf_information_fixtures.py` from the project root. This optional developer script requires `pypdf[crypto]`, Ghostscript on PATH and macOS's system sRGB profile; none is a new application runtime dependency. Existing fixtures were generated using pypdf 6.10 and Ghostscript 10.07.1. Regeneration changes encryption salts and timestamps.

| Fixtures | Purpose |
| --- | --- |
| InfoPlain | Used nonembedded Helvetica; unused nonembedded Courier; custom Unicode metadata |
| InfoNestedFont | Font used inside a Form XObject |
| InfoType0 / InfoType3 | CID descendant-font lookup; embedded Type-3 character descriptions |
| InfoEmbeddedSubset / InfoEmbeddedFull | Ghostscript-generated subset/full font-program embedding |
| InfoInlineImage | Inline-image lifetime and effective resolution |
| InfoClaimedPDFA | PDF/A-2b XMP claim with nonembedded text: report the claim without validating it |
| InfoXMPTitle | Overview title available only through an RDF alternative in XMP |
| InfoICC | macOS system sRGB profile reused by an ICCBased color space and an output intent |
| InfoEncrypted-RC4-40 / RC4-128 / AES-128 / AES-256 | Locked, wrong, user and owner authentication; original permission bits |
| InfoEncryptedXRefStream / InfoEncryptedIncremental | Original AES-128 objects with a compressed cross-reference stream or appended catalog revision |
| InfoEmptyPassword | Empty opening password, owner protection |
| InfoUnicodePassword | UTF-8 opening/owner passwords, including punctuation and supplementary Unicode characters |

Ordinary encrypted fixtures use opening password `user-test` and owner password `owner-test`. InfoEmptyPassword uses an empty opening password and `owner-test`. InfoUnicodePassword uses opening password `Päss (\) € 🔒` (one literal backslash) and owner password `Öwner 🔑`. These strings are public fixture data, not credentials for any account.

The embedded font examples contain a Ghostscript-provided substitute font program and only the synthetic text above. The ICC example embeds the system sRGB profile solely to exercise inspection; the app already uses ICC profiles as part of its existing workflow.


## Independent-review regression fixtures

`Review/` contains the 14 original synthetic counterexamples from the independent review dated 2026-09-05, copied byte-for-byte from its evidence package. They are checked by `PDFInspectionReviewTests`; the original fixture generator above does not regenerate them.

| Fixture | Regression |
| --- | --- |
| oversized-encryption-length | Malformed R2 `/Length` around 1e100; previously crashed the process |
| unreadable-xmp-stream / unreadable-icc-profile | Present but unreadable metadata must remain unknown/incomplete |
| form-inherits-resources | Used nonembedded Helvetica in a Form without its own Resources |
| unicode-bookmarks-labels | AES-256 Unicode password, bookmark and `A-i` page label |
| direct-colors | DeviceRGB, DeviceCMYK, DeviceGray content operators |
| xmp-split-description / xmp-conflicting-properties | RDF-subject merging and preservation of conflicting values |
| xmp-unrelated-namespace | A custom namespace must not create a PDF/UA claim |
| type3-image-resolution | Type-3 text transform is not evaluated: explicit unknown PPI |
| inherited-field-type | Qualified child field name, inherited type and child value |
| cryptfilter-recipient | Recursive exclusion of the synthetic `REVIEW-RECIPIENT-DATA` marker |
| many-incomplete-pages | 35 notices remain accessible without displacing the AppKit table |
| version-lower-override | A lower catalog version cannot lower the effective version |

`unicode-bookmarks-labels` uses the same public Unicode test passwords as InfoUnicodePassword. `cryptfilter-recipient` uses `user-test` / `owner-test`. `oversized-encryption-length` opens with an empty password. None contains real credentials, keys or user content. The crash fixture is now safe to include in the regression run, provided the reviewed fix is present.
