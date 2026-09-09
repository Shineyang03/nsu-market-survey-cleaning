# reference/archive

Inputs that were pulled in to answer a specific question, are no longer read by anything,
and are kept only so the question can be re-answered without re-sourcing them.

**Nothing in this folder is a pipeline input.** If a file here starts being read by a
do-file or a script, move it out — `reference/` proper is for live inputs.

The data files themselves are **gitignored**, deliberately: they are large, externally
sourced, and re-downloadable. This README is the record. If you need one of them, the
provenance below says where it came from.

| file | size | source | what it was for |
| :-- | :-- | :-- | :-- |
| `WB_2025_PH_Food_Prices.csv` | 19.5 MB | World Bank food price data for the Philippines, 2025 | Pulled while looking at issue #34 — whether the PSPS price range covers the same range of weights as the market-survey weighings. The question was answered from `docs/WB-NSU-Guide.pdf` instead: the guide's method, not this price series, is what #34 turned on. Never read by any do-file or script. |
