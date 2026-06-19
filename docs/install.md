# Install, channels, update, uninstall

The installer is non-destructive: it fetches the repo to a temp dir, bootstraps WezTerm without
`sudo`, installs the `wez` CLI, injects a single guarded block into your `wezterm.lua` (backing
up the original first), and verifies with `wez doctor`. Everything lands under `~/.local` and
`~/.config` — nothing system-wide, no `sudo`, ever.

---

## One-line install

```sh
curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh | bash
```

Prefer `wget`? Same result:

```sh
wget -qO- https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh | bash
```

If a previous install exists, or you want the interactive WezTerm version selector, use the
**process-substitution** form so prompts stay interactive (a piped `curl … | bash` consumes
stdin, so the re-install / version prompts only appear with this form or a real terminal):

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh)
```

### Requirements

- `curl` **or** `wget`, plus `tar` (standard on Linux and macOS).
- Linux (Wayland + X11) or macOS.
- No `sudo` — everything installs under `~/.local` and `~/.config`.

---

## Choosing a WezTerm version: `WEZ_CHANNEL`

`WEZ_CHANNEL` selects which WezTerm the installer bootstraps:

```sh
WEZ_CHANNEL=nightly  bash <(curl -fsSL .../tools/install.sh)   # default: rolling nightly
WEZ_CHANNEL=stable   bash <(curl -fsSL .../tools/install.sh)   # latest stable release
WEZ_CHANNEL=v20240203-110809-5046fc22 bash <(curl -fsSL .../tools/install.sh)  # pin an exact version
```

- `nightly` (default) — the rolling nightly; a behind-the-latest install **in your user path** is
  updated in place. A **system** WezTerm (e.g. from `apt`) is never touched.
- `stable` — the latest stable release.
- `<vX.Y.Z>` — pin an exact WezTerm version tag.

---

## Trust model

This is `curl | bash` — you are running a script fetched over the network. HTTPS protects the
**transport**, not the authenticity of the content. Two cheap habits make it safe.

**Inspect before you run:**

```sh
curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh -o install.sh
less install.sh
bash install.sh
```

**Pin the installer to a tag or commit** with `WEZ_REF`, so the byte you read is the byte you run:

```sh
WEZ_REF=v1.0.0 bash <(curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh)
```

`WEZ_REF` accepts a tag or a full commit SHA; the installer fetches the matching source snapshot.
The downloaded `wez` release binary is **SHA-256 verified before `chmod +x`** — a wrong or tampered
binary aborts the install. Pinning plus inspection close the residual content-authenticity gap
that HTTPS alone leaves open.

---

## Local / development install

Already have the repo cloned? Use the local path:

```sh
git clone https://github.com/castocolina/wezterm-setup
cd wezterm-setup
make install
```

---

## Updating

Once installed, self-update with:

```sh
wez update
```

This refreshes the `wez` binary, the managed config, and WezTerm (to a newer nightly when one is
available, consistent with the channel you installed).

---

## Uninstalling

The `wez` front door removes everything (and works from a binary-only install):

```sh
wez uninstall                  # confirm, then remove the managed block, config, binary, backups
wez uninstall --yes            # skip the prompt (required on a non-TTY pipe)
wez uninstall --keep-config    # keep ~/.config/wezterm/wezterm-setup/
wez uninstall --keep-cli       # keep the wez binary
wez uninstall --keep-backup    # keep wezterm.lua.bak.* backups
```

From a cloned repo, the `make` targets are equivalent:

```sh
make uninstall                 # remove everything
make uninstall KEEP_CONFIG=1   # keep the config dir
make uninstall KEEP_CLI=1      # keep the wez binary
make uninstall KEEP_BACKUP=1   # keep wezterm.lua.bak.* backups
```

The installer always wrote a timestamped `wezterm.lua.bak.<timestamp>` before injecting its block,
so your original config is recoverable regardless. See [troubleshooting.md](troubleshooting.md) if
`wez doctor` reports a problem.
