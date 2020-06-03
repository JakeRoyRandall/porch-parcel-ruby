# Porch Parcel

Porch Parcel is a fictional, offline 2020 delivery themed Ruby terminal shelf packer created retrospectively in September 2026. The author date is deliberate calendar art, not a historical work record.

The core accepts JSON with integer `shelf_width`, integer `shelf_height`, and up to 30 rectangular parcels with unique string IDs and positive integer `width`/`height`. Shelves are bounded to 40×20. Parcels are placed deterministically using first-fit row-major scanning; rotation is intentionally deferred. The output prints an ASCII occupancy grid, placements, and unplaced IDs.

Run:

```sh
ruby app/packer.rb input.json
```

Test:

```sh
ruby -Itest test/test_packer.rb
```
