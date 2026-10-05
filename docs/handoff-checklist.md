# cassie-box hand-off checklist

Goal: mail the OptiPlex 7060 to Cassie, she plugs in ethernet and power, and it
comes up on her LAN and the tailnet with every service working, and Izzy can
maintain it from afar without anyone touching it.

State as reviewed on 2026-09-15 (generation 93, deployed 2026-09-06, uptime 9d).
Items are ordered by how badly they hurt a headless box.

## A. Must fix in the config before shipping

- [ ] **Auto-upgrade has never worked.** `nixos-upgrade.service` fails every
      hour with `unrecognized arguments: -accept-flake-config` (single dash) in
      `nixos/modules/nixos/system/autoupgrades/default.nix`. The box is stuck on
      the 2026-09-06 generation; the romm and RStudio/Jupyter commits from
      2026-09-15 were never deployed. Fix the flag, then decide on
      `allowReboot = true` with a `rebootWindow` (e.g. 04:00-05:00) so kernel
      updates actually take effect; today nothing ever reboots.
- [ ] **Backups do not exist.** All 62 `restic-backups-*` units fail nightly.
      `mySystem.system.resticBackup.{local,remote}.location` are both `""`, so
      each repository resolves to `//mnt/data/appdata/<app>` and `restic init`
      has scattered repo skeletons (`config data index keys locks snapshots`)
      into the app data folders. The source path `/mnt/data/nightly_backup/...`
      is the upstream ZFS-snapshot design and does not exist here. Vaultwarden's
      real data lives in `/var/lib/bitwarden_rs` and is backed up nowhere.
      Postgres dumps (`/mnt/data/backup/nixos/postgresql`) are the only working
      backup. Decide: point restic at a real local repo plus B2 (the restic env
      secret already carries B2 creds), back up live paths (sqlite via
      `--use-fs-snapshot`-less copy or app-native export), and clean the stray
      repo dirs out of `/mnt/data/appdata/*` and `/var/lib/vaultwarden`.
- [ ] **Tailscale key expires 2027-02-27.** When it does, the box silently drops
      off the tailnet and remote maintenance is over. In the admin console:
      disable key expiry for the node, or better, tag it (tagged nodes never
      expire). Also delete the stale `cassie-box` node so this one stops being
      `cassie-box-1` (boat-ray peers address each other by MagicDNS name).
- [ ] **Wired NIC is untested.** `eno2` has no carrier right now; the box is on
      WiFi `meow`. `net-diag.nix` was added because the wired link was
      unstable. At Cassie's there is no known WiFi, so ethernet must be solid:
      run on cable only for a few days (`nmcli con down meow`) and read
      `/var/log/net-diag.log`. Optionally pre-provision Cassie's SSID/password
      as a fallback via `networking.networkmanager.ensureProfiles` + sops.
- [ ] **code-server is an unauthenticated root shell.** `auth = "none"`, runs as
      `cassie`, who is in `wheel` with `wheelNeedsSudoPassword = false`, and it
      is proxied at `https://code-cassie-box.cassies.app` to the whole LAN
      (confirmed: returns 200 with no login). Set `auth = "password"` with a
      sops-managed hash, or disable it, and consider turning sudo passwords
      back on.
- [ ] **Cassie's SSH key is not Cassie's.** `users.users.cassie.openssh.authorizedKeys`
      holds `truxnell@home`, the upstream template author's key. Replace with
      her key or remove it.
- [ ] **Template leftovers still point at trux.dev / 10.8.x.**
      - `containers/qbittorrent/qbtools.nix`: `--server https://qbittorrent.trux.dev`
        (four timers fail daily on DNS).
      - `containers/qbittorrent/lts.nix`: cross-seed webhook to `cross-seed.trux.dev`.
      - `containers/plex/default.nix`: `PLEX_ADVERTISE_URL` hardcodes `10.8.20.42`.
      - `containers/searxng/default.nix`: `base_url = https://searxng.trux.dev`.
      - `containers/rxresume/default.nix`: `s3.trux.dev` (module unused, low priority).
      - `services/adguardhome`, `services/blocky`, `containers/gatus`: `10.8.10.1`,
        `unifi`, `pikvm` (all unused on this host, fine to leave).
- [ ] **Nobody gets told when something breaks.** `vmagent` remote-writes to
      `shodan`, which does not resolve, so local VictoriaMetrics is empty
      (`count(up)` returns nothing), Grafana is blank and vmalert never fires.
      The pushover unit-failure module is not imported by
      `nixos/modules/nixos/system/default.nix`, and gatus is not enabled. Fix:
      `remoteWrite.url = http://127.0.0.1:8428/api/v1/write` in
      `services/monitoring.nix` (and `services/paperless`), import and enable
      the pushover module, and add an alert rule on `node_systemd_unit_state{state="failed"}`.
- [ ] **calibre-web is dead** (start-limit-hit, pre-start exit 226/NAMESPACE,
      probably a missing `/mnt/data/media/books/`). Fix the path or confirm
      before disabling.
- [ ] **Vaultwarden open registration.** No `SIGNUPS_ALLOWED` in the env, so
      the default (true) applies and anyone on the LAN can create an account.
      After Cassie's account exists, set `services.vaultwarden.config.signupsAllowed = false`.
- [ ] **Jupyter has no password.** `passwordHash` is empty, so it is token-only
      and the token lives in the journal on the box. Set the hash before shipping.
- [ ] **Grafana admin password is the default `admin`.** Set `security.admin_password`
      from sops or change it on first login.

## B. Hardening for a box nobody can walk over to

- [ ] **Hardware watchdog.** `/dev/watchdog` exists. Set
      `systemd.settings.Manager.RuntimeWatchdogSec = "30s"` so a hung kernel
      reboots itself instead of waiting for a human.
- [ ] **`nofail` on the data mounts** (`/mnt/data1`, `/mnt/data2`, the mergerfs
      pool). Today a dead NVMe stops `local-fs.target`; with `nofail` SSH and
      tailscale still come up so the failure can be diagnosed remotely.
- [ ] **`boot.loader.systemd-boot.configurationLimit`** (e.g. 10). Hourly
      upgrades plus `/boot` at 1 GB will eventually fail to write a new entry.
- [ ] **Tailscale SSH as a second door.** `tailscale up --ssh` (or
      `services.tailscale.extraSetFlags = [ "--ssh" ]`) means a broken sshd or
      lost key does not lock Izzy out.
- [ ] **Deploy from a stable ref, not `main`.** Every push to `main` goes live
      within the hour. Point `system.autoUpgrade.flake` at
      `github:izzyhub/cassie-box/stable` and fast-forward `stable` only after a
      local `nixos-rebuild build --flake .#cassie-box`. Note the first upgrade
      after the flag fix builds ~1560 derivations (R packages, boat-ray) on the
      box: hours of full CPU. Consider pushing to a cache first.
- [ ] **Firewall.** 8428 (VictoriaMetrics, no auth) and 8081 are open to the
      LAN. Close unless needed.
- [ ] **DNS rebind protection.** `*.cassies.app` resolves to a private
      `10.x` address on purpose. Some routers (Fritz!Box, pfSense/OPNsense, some
      ISP gateways) drop such answers. Fallback is `http://cassie-box.local`
      via mDNS, which will show certificate warnings. Test at her place; if it
      fails, whitelist `cassies.app` in her router's rebind settings.
- [ ] **Subnet collision.** Podman uses `10.88.0.0/16`; if Cassie's LAN is in
      that range containers lose the LAN. Unlikely, but worth knowing.
- [ ] **BIOS (must be done before boxing it up, cannot be done remotely).**
      Dell OptiPlex 7060, BIOS 1.12.0: set *AC Recovery* to *Power On*, disable
      *Deep Sleep*, and confirm the box boots with no keyboard attached and no
      "press F1" prompt.
- [ ] **Homepage widget nits.** Fairfax longitude should be `-77.3053`
      (positive puts it in Uzbekistan); locale `au` and metric units in the US.
- [ ] **Stale docs.** `docs/internal-setup-guide.md` says dynamic DNS is
      disabled and tells Cassie to run `sudo tailscale up`; both wrong now.
      `CLAUDE.md` deploy commands reference `/etc/nixos`, which does not exist
      on the box. Replace with the welcome page and a short admin page.
- [ ] **Leave a bootable NixOS USB stick in the box** for the day nothing boots.

## C. Things to write down

Keep in Izzy's own vault; give Cassie a sealed card with the starred lines.

- [ ] * Vaultwarden URL `https://vaultwarden.cassies.app`, Cassie's initial
      master password (she changes it on first login).
- [ ] Vaultwarden `ADMIN_TOKEN` (in `services/vaultwarden/secrets.sops.yaml`).
- [ ] * Cassie's Linux password (sops `cassie-password`). Used by RStudio
      (PAM), the console, and sudo if that gets turned back on.
- [ ] * Jupyter password. Grafana admin password. Filebrowser admin
      (default `admin`/`admin` unless changed). Immich admin. Paperless admin
      (`services/paperless/passwordFile`). Tandoor, Vikunja, Linkding,
      Navidrome, Romm, Overseerr, Sonarr/Radarr/Lidarr/Readarr/Prowlarr,
      SABnzbd, qBittorrent x2. Put all of these into Vaultwarden itself and
      the card only needs the Vaultwarden password.
- [ ] Plex: which account claims the server, and whether Cassie is a managed
      user or home member.
- [ ] Redbot Discord token owner. Boat-ray peer (`sophie-001-1`) owner.
- [ ] Tailscale: tailnet owner account (`izzyhub@`), how Cassie joins
      (invite as user, or share the node), node name, key-expiry setting.
- [ ] Cloudflare: account for `cassies.app`, the API token (DNS:Edit on the
      zone) used by both ACME and ddclient, and its expiry if any.
- [ ] Box identity: hostname `cassie-box`, mDNS `cassie-box.local`, tailnet
      `cassie-box-1.tail6b6f7.ts.net` (rename after removing the stale node),
      SSH host key `SHA256:LydJqj0nfnjQzrL/bk0tl3E/v91kKQamluEjTWHMtbk`.
- [ ] **Back up `/etc/ssh/ssh_host_ed25519_key` offline.** It is the sops age
      key for every secret on the box. A reinstall without it means
      re-encrypting everything from the MBP key and re-deploying.
- [ ] Recovery notes for a phone call: how to pick an older generation in the
      systemd-boot menu, and `systemctl --failed` / `journalctl -b -p err`.

## D. What Cassie has to do

1. Plug in ethernet (to the router, not a powerline adapter if avoidable) and
   power. Wait five minutes. The box has no screen output worth reading.
2. On a phone or laptop on the same WiFi open `https://homepage.cassies.app`.
   If that does not load, try `http://cassie-box.local`. If neither loads after
   ten minutes, unplug power for thirty seconds, plug back in, wait again, then
   text Izzy.
3. Open `https://vaultwarden.cassies.app`, log in with the password on the
   card, change it, and install the Bitwarden app pointed at that URL. Every
   other login lives in there.
4. Sign in to Plex on the TV with the account named on the card.
5. Optional, for access away from home: install Tailscale on her phone and
   laptop and accept Izzy's invite.
6. Never needs to: update anything, run commands, touch the router config
   (unless the DNS rebind fallback in B is needed).

## E. Pre-ship test protocol

- [ ] Apply section A, `nixos-rebuild build --flake .#cassie-box` locally,
      deploy, then watch `nixos-upgrade.service` succeed on its own timer.
- [ ] `systemctl reset-failed`; next morning `systemctl --failed` is empty and
      `restic snapshots` shows last night's snapshots. Do one restore.
- [ ] Cold-boot test: pull power, wait 30 s, restore. No keyboard, no monitor.
      All services reachable within five minutes; `tailscale status` online.
- [ ] Cable-only test for at least 24 h with the WiFi profile down.
- [ ] Foreign-network test: plug into a phone hotspot or a spare router on a
      different subnet (192.168.x). Confirm ddclient publishes the new address,
      `https://homepage.cassies.app` opens without warnings, tailnet SSH works,
      boat-ray reaches its peer.
- [ ] From outside the house over the tailnet: `ssh cassie-box-1`, and a
      `nixos-rebuild switch --flake .#cassie-box --target-host` round trip.
- [ ] Confirm a Pushover message arrives when a unit is deliberately failed
      (`systemctl start restic-backups-doesnotexist` or similar).
- [ ] Box it with the USB stick and the sealed card.
