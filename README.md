# Porch Parcel

Porch Parcel is a fictional, offline 2020 delivery themed Ruby terminal shelf packer created retrospectively in September 2026. The author date is deliberate calendar art, not a historical work record.

The core accepts JSON with integer `shelf_width`, integer `shelf_height`, and up to 30 rectangular parcels with unique string IDs and positive integer `width`/`height`. Shelves are bounded to 40×20 and parcel dimensions to 40×40. Parcels are placed deterministically using first-fit row-major scanning; parcels larger than the shelf remain unplaced. Rotation is an optional feature: `--rotate` tries the original orientation first at each position, then 90 degrees; `--show-orientation` includes actual dimensions in placement output. The output prints an ASCII occupancy grid, placements, and unplaced IDs.

Run:

```sh
ruby app/packer.rb [--rotate] [--show-orientation] [--html report.html] [--force] input.json
```

Test:

```sh
ruby -Itest test/test_packer.rb
```

`--html` writes a standalone warm porch-style shelf report with proportional parcel rectangles, labels, dimensions, orientation, unplaced IDs, and occupied/total area. It has no external assets and will not replace an existing report unless `--force` is supplied. Terminal output is still printed as usual.
