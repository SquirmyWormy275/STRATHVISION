# Bundled interface fonts

Run `python scripts/fetch_ui_fonts.py` from the repository root before Flutter asset resolution. CI runs this step. It retrieves exact pinned Git blobs for Barlow Semi Condensed from google/fonts and Source Sans 3 from adobe-fonts/source-sans, verifies each blob identity and keeps both SIL Open Font License notices. The built application bundles the fonts and notices; it never downloads fonts at runtime. Existing unexpected local assets are refused rather than overwritten. Generated font/license files are excluded from Git; no system font files are used.
