# One zip, one mod root: how lovely finds mods (and why the suite ships as one folder)

From lovely's loader (`crates/lovely-core/src/patch/loader.rs`, read 2026-09-26):

- **Folders.** Each direct child of `Mods/` is a mod. Its patch files are `lovely.toml` and every `lovely/**/*.toml`,
  and every `source` resolves from that folder, not from the patch file's own directory. So one folder can hold
  several mods' patch files, with `lovely/SeedOracle.toml` pointing at `SeedOracle/src/oracle.lua`. HandyBalatro
  ships that way.
- **Zips.** A `.zip` directly in `Mods/` is loaded without being unzipped. lovely looks for **one** mod root, the
  first directory holding `lovely.toml` or `lovely/`, and it may sit inside a folder in the zip. So a zip holding
  five mod folders side by side loads only one of them.
- Nothing deeper is scanned: `Mods/X/Y/lovely.toml` is ignored. That catches people whose unzipping adds an extra
  level.

That's why the release is a single `BalatroSeedSuite/` folder, with each `mods/<Mod>/lovely.toml` rewritten as
`lovely/<Mod>.toml` (sources prefixed `<Mod>/`, `scripts/release.py`). The same zip works dropped into `Mods/` or
unzipped there. The rig reads `lovely/*.toml` the same way, so `make smoke-dist` boots the actual bundle.
