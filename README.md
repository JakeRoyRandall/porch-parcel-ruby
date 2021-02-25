# Porch Parcel

Porch Parcel is a fictional, offline 2020 delivery themed Ruby terminal shelf packer created retrospectively in September 2026. The author date is deliberate calendar art, not a historical work record.

The core accepts integer `shelf_width`, integer `shelf_height`, and up to 30 rectangular parcels with unique string IDs and positive integer `width`/`height`. Shelves are bounded to 40×20 and parcel dimensions to 40×40. An optional `blocked` array reserves fixed shelf cells, each as an integer `{ "x": 0, "y": 0 }`; coordinates must be in bounds and unique. Parcels never cover blocked cells. An optional parcel `rotatable` boolean defaults to true; `--rotate` cannot turn a parcel whose rotation is locked. Parcels are placed deterministically using first-fit row-major scanning; parcels larger than the shelf remain unplaced. Rotation is an optional feature: `--rotate` tries the original orientation first at each position, then 90 degrees for rotatable parcels; `--show-orientation` includes actual dimensions in placement output. The output prints an ASCII occupancy grid, placements, and unplaced IDs.

Run:

```sh
ruby app/packer.rb [--strategy first-fit|area|best-fit] [--sort input|area|long-side] [--compare] [--rotate] [--margin 0..3] [--min-fill 0..100] [--show-orientation] [--json|--csv] [--html report.html] [--svg shelf.svg] [--force] input.json
```

Test:

```sh
ruby -Itest test/test_packer.rb
```

`--validate-only` checks each parcel independently against the shelf, blocked cells, margin, and rotation-lock rules without producing a packing layout. It prints `fits-alone` rows, or JSON with `--json`; it cannot be combined with strategy, compare, HTML, SVG, `--show-orientation`, or `--force` options.

`--html` writes a standalone warm porch-style shelf report with proportional parcel rectangles, labels, dimensions, orientation, unplaced IDs, occupied/total/usable area, and a visibly striped, accessible marker for each blocked cell. It has no external assets and will not replace an existing report unless `--force` is supplied. Terminal output is still printed as usual.

`--json` replaces the terminal report with one deterministic JSON object containing shelf dimensions, strategy, blocked coordinates, placed parcel geometry and rotation flags, unplaced IDs, occupied area, and usable area. Diagnostics remain on stderr, so stdout can be piped to another tool.

`--csv` replaces the terminal report with CRLF CSV rows using `id,x,y,width,height,rotated,status` columns. It lists placed parcels first and unplaced parcels with blank coordinates/rotation; blocked cells are not rows. CSV is single-run output and cannot be combined with JSON, compare, or validate-only. Add `--unplaced-only` with `--csv` to retain the header while emitting only unplaced rows; the filter is rejected for other output modes.

`--compare` packs the same input with `first-fit`, `area`, and `best-fit`, then reports occupied area, placed count, unused usable area, and unplaced IDs side by side. Add `--json` for structured comparison or `--html report.html` for three readable shelf panels. It shares rotation and margin options and cannot be combined with `--strategy`.

`--svg shelf.svg` writes a standalone scalable shelf diagram for one strategy, with a padded outer canvas, visible shelf grid, blocked cells, parcel markers, an escaped legend, orientation and rotation-lock details, unplaced IDs, and occupied/usable summary. The canvas reserves enough width and height for narrow shelves and long legends. It cannot be combined with `--html` or `--compare`; existing files require `--force`.

`first-fit` is the default and preserves input order. `area` stably sorts parcels by decreasing area before using the same deterministic placement scan. `best-fit` preserves input order but evaluates every valid candidate for each parcel, choosing the smallest contiguous free gap immediately to the right across its rows, then the analogous gap below, then top-left position; the requested margin is excluded from those measured gaps. It is a deterministic packing heuristic without an optimality guarantee. Reports identify the chosen strategy.

`--sort` optionally controls parcel order independently of the placement strategy: `input` preserves the original order, `area` sorts by decreasing rectangle area, and `long-side` sorts by decreasing longest dimension. Ties retain input order. The default strategy-derived ordering is unchanged (`area` strategy still defaults to area ordering), and JSON keeps its existing `strategy` label while adding `sort` only when explicitly requested.

`--margin N` requires N empty shelf cells between each parcel and the shelf boundary, blocked cell, or another parcel; N is an integer from 0 through 3 and defaults to 0. Only the parcel rectangle counts as occupied area. Margin is reported in text, JSON, and HTML output.

`--min-fill PERCENT` is an optional batch acceptance threshold from 0 through 100. Normal output is still produced, then the process exits 1 when placed parcel area divided by usable shelf area falls below the threshold; usable area is total shelf cells minus blocked cells. It is available for a single packing run and cannot be combined with compare or validate-only.
