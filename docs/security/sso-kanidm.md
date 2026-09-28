# SSO with Kanidm on cassie-box: plan and checklist

> Adapted on 2026-09-28 from the izzy-nix-config plan (`~/izzy-nix-config/docs/security/sso-kanidm.md`,
> phases 1-5 live there). The modules can be ported from that repo: `services/kanidm`,
> `services/oauth2-proxy`, `services/sso`, and `mkVhost`/`oidcIssuer` in `lib.nix`.
> **Nothing in this doc is implemented yet.** Tick the boxes as things land.

## What is different from the source plan

| Source (huci + sophie) | cassie-box | Consequence |
|---|---|---|
| IdP on huci, forward-auth on sophie, LDAP over the tailnet | **One host**: Kanidm, oauth2-proxy and nginx all on cassie-box | Drop `tailnetListen`, `externalResponder`, LDAP on the tailnet, and the "deploy huci first" ordering. Everything binds to loopback. |
| `mkVhost { sso = true; ssoBypass = [...]; }` builds every vhost | **No `mkVhost`**. Each of the ~40 modules writes its own `services.nginx.virtualHosts.<url>` with a `"^~ /"` location | Port `mkVhost` first and convert the vhosts to it (§2). |
| `izzys.place`; per-name A record needed for `idm.` on huci | `cassies.app`; ddclient already publishes `cassies.app` + `*.cassies.app` to the box | Nothing to do in DNS. `idm.cassies.app` and `auth.cassies.app` already resolve. |
| DNS rebinding made oauth2-proxy crash-loop on startup discovery | Same risk, and worse: nobody can get to the box (checklist B, "DNS rebind protection") | Pin `idm.cassies.app` and `auth.cassies.app` to `127.0.0.1` in `networking.hosts` so the server-side hops never use LAN DNS. |
| Working restic backups | **Backups do not exist** (checklist A) | Kanidm holds the passkeys. Get restic working before the IdP holds anything you can't recreate. |
| Admin sits next to the box | Headless box, maintained over the tailnet | Every gated app needs a way in when Kanidm or oauth2-proxy is down. See §5. |
| ~55 apps, many with mobile or API clients | ~40 vhosts; the people using them are Cassie and Izzy | Two groups is plenty. Radicale, ntfy, gitea, mealie, miniflux, homarr, komga, manyfold and actual aren't enabled here, so those sections are gone. |

## 0. Decisions

| Decision | Choice | Why |
|---|---|---|
| IdP | Kanidm `kanidm_1_11.withSecretProvisioning` (1.11.1 in nixos-26.05, already checked) | Same as the source. Declarative provisioning, passkeys. |
| Origin | `https://idm.cassies.app`. kanidmd runs its own TLS on `127.0.0.1:8443` with the existing `cassies.app` wildcard (`/var/lib/acme/cassies.app`) | The wildcard cert already exists (`security/acme`, `extraDomainNames = [ "*.cassies.app" ]`). **Choose the name before anyone enrols.** Passkeys are bound to it, and renaming later throws them all away. |
| Forward-auth | `services.oauth2-proxy` on `127.0.0.1:4180`, portal `https://auth.cassies.app`, cookie domain `.cassies.app` | Same as the source, but local, so `verifyUrl` is loopback. |
| Secrets | `withSecretProvisioning` + `basicSecretFile`; one sops value feeds both the Kanidm client and the app | The existing `.sops.yaml` rule (`.*\.sops\.yaml$` → MBP + cassie-box keys) already covers new module files. |
| Groups | `admins` = izzy + cassie. `household` = izzy + cassie (admins ⊂ household) | Decided 2026-09-28: Cassie is in `admins` because it's her box. With both people in both groups, the split only matters for future guest/family logins. Infrastructure (code-server, metrics, *arr settings) still maps to `admins`, so a guest in `household` never gets a root shell. |
| Vaultwarden | **Never behind SSO** (neither forward-auth nor Vaultwarden's own OIDC) | Every other password lives in it (checklist C/D). It has to keep working when the IdP is broken. |
| PAM/NSS (source phase 7) | **Skip** | It's the only phase that touches host login, and this box can't be reached if login breaks. RStudio stays on local PAM for `cassie`. |

## 1. How much is nix-only here?

| Tier | Apps on this box | What it takes |
|---|---|---|
| **A: forward-auth gate, pure nix** | code-server, jupyter, filebrowser, homepage, silverbullet, syncthing GUI, calibre (KasmVNC), changedetection, maintainerr, boat-ray UI, searxng, whoogle, redlib, victoriametrics / vmalert / alertmanager / vmagent, *arr stack, sabnzbd, qbittorrent ×2 | `sso = true` (+ `ssoBypass`, `ssoGroup`) in each module's `mkVhost` call. The *arrs also get `settings.auth.method = "External"`. |
| **B: native OIDC from nix** | grafana, paperless, immich, romm, tandoor, vikunja | Kanidm client and env/settings in the app module. Some need a one-time account link in the UI. |
| **B': header auth behind the gate** | navidrome, linkding, calibre-web | The app trusts `X-Auth-Request-Preferred-Username` from loopback. Clients get a bypass. |
| **C: leave alone** | vaultwarden, plex, tautulli, overseerr (Plex accounts), jellyfin (TV clients), rstudio-server (PAM only in the open-source build), languagetool (API used by editor plugins), invidious (own accounts; optional gate) | Nothing. |

The same things stay manual as in the source: each person enrols their own credential with a reset link.

## 2. The seam: port `mkVhost` first

Decided 2026-09-28: port `config.lib.mySystem.mkVhost` from izzy-nix-config and convert the hand-rolled vhosts to it. This happens **before** phase 1, as its own change.

Why:
- About 40 of the ~50 vhost blocks are the same 7-9 lines (`forceSSL`, `useACMEHost`, one `"^~ /"` location), differing by at most `resolver 10.88.0.1;` or `proxyWebsockets`. Each becomes one call.
- The SSO wiring comes with it and is already proven there: `sso`, `ssoBypass`, the literal `proxy_pass` for the internal auth location (this repo also has `proxyResolveWhileRunning = true`, so the source's "blank page, `202 0`" bug applies here too), and the `X-Auth-Request-*` header passthrough.
- The gate sits in the app's own module, next to the things that depend on it: the *arr `External` auth mode and the gatus conditions can read the module's own `sso` flag.

Changes from the source helper:
- **`ssoGroup`** (new, optional). Appends `?allowed_groups=<group>@idm.cassies.app` to the verify URL for that vhost. This is oauth2-proxy's per-request group check: code-server and the metrics UIs use `ssoGroup = "admins"`, everything else defaults to the portal-wide `household`.
- `upstreamHost` stays (it's how container names are reached), but there's no front-door use for it on a single host.

Rules for the conversion:
- **Proof is a byte-identical `nginx.conf`.** Render the config before and after (with `sso.enable = false`) and diff them. Any line that changes has to be explained.
- Vhosts with real custom config stay hand-written: vaultwarden, boat-ray, and anything else whose diff can't be made empty without contorting the helper.
- The `sso` module is ported at the same time as an **inert** options-only module (`enable = false`), because `mkVhost` reads it. The oauth2-proxy responder and its assertions come in phase 3.
- Reviewing what's gated: once the flags go in (phase 4), add a read-only `mySystem.services.sso.gatedHosts` option that `mkVhost` feeds, so `nix eval .#nixosConfigurations.cassie-box.config.mySystem.services.sso.gatedHosts` prints the list before shipping.

## 3. Build phases

### Phase 0: prerequisites from the hand-off checklist
- [x] `mkVhost` ported and 42 modules converted (§2), not yet committed or deployed. The rendered `nginx.conf` is identical except for two expected kinds of change:
      container vhosts' `resolver 10.88.0.1;` and two `client_max_body_size` lines moved from location to server level (same effect);
      and the unneeded resolver dropped from the loopback vhosts grafana, navidrome, paperless, syncthing, vikunja and redis.
      Also checked with every imported-but-disabled vhost module switched on.
      Still hand-written: vaultwarden, boat-ray, searxng, rss-bridge (nixpkgs owns that vhost), and minio/open-webui/thelounge/audioreadarr (not imported, so the diff can't check them).
- [ ] Restic backups working (checklist A). Kanidm's `online_backup` directory has to land in a repo that actually exists.
- [ ] Unit-failure alerting working (checklist A). A dead oauth2-proxy returns 500 on every gated vhost, and someone needs to find out.
- [ ] Autoupgrade flag fixed, and ideally the `stable` ref (checklist B). Otherwise each phase below goes live within the hour of being pushed to `main`.

### Phase 1: Kanidm (nix)
- [ ] Port `services/kanidm/default.nix`, with these changes:
      drop `ldap.*` and `tailnetListen`;
      `environment.persistence` uses `mySystem.persistentFolder` (as the other modules here do);
      its vhost is `mkVhost { app = "kanidm"; subdomain = "idm"; port = 8443; scheme = "https"; websockets = true; }` as in the source;
      `mkRestic` here is `nixos/modules/nixos/lib.nix:40`, so check that its arguments match.
- [ ] `networking.hosts."127.0.0.1" = [ "idm.cassies.app" "auth.cassies.app" ];`
- [ ] `services/kanidm/secrets.sops.yaml`: `admin-password` and `idm-admin-password` (`openssl rand -hex 32`).
- [ ] Add the module to `services/default.nix`, and set `mySystem.services.kanidm.enable = true` in the host.
- [ ] **Manual**: `nixos-rebuild build --flake .#cassie-box` locally, deploy, then check that `https://idm.cassies.app` loads on the LAN.

### Phase 2: people and groups
- [ ] `persons.izzy = { groups = [ "admins" "household" ]; ... }` and `persons.cassie = { groups = [ "admins" "household" ]; mailAddresses = [ <Cassie's email> ]; }`.
      The email matters: romm, paperless and immich match existing accounts by email.
- [ ] **Manual, izzy**: on the box, `kanidm login --name idm_admin`, then `kanidm person credential create-reset-token izzy`. Set a password and a passkey.
- [ ] **Manual, Cassie**: `kanidm person credential create-reset-token cassie --ttl 86400` (the TTL is in seconds), then send her the link.
      The link only opens where `idm.cassies.app` resolves: on her LAN once the box is there, or on the tailnet.
      Two ways to do it:
      (a) before shipping, if she can do it from Izzy's network, or
      (b) as a new step in checklist §D, just after step 3 (Vaultwarden). Store the Kanidm password in Vaultwarden. A passkey on her phone is better.
      Either way, write the fallback in checklist §C: reset tokens can be reissued remotely at any time, so a lost credential is a phone call, not a trip.

### Phase 3: forward-auth responder
- [ ] Port `services/oauth2-proxy`: drop `tailnetListen` and `trustedProxyIP` beyond loopback. Keep the restart settings: `Restart=always`, `RestartSec=5s`, no start limit.
- [ ] Finish `services/sso` (the options were ported with `mkVhost` in §2): add the "responder enabled on this host" assertion. The `externalResponder` option and the authelia provider go away.
- [ ] Portal vhost `auth.cassies.app` → `127.0.0.1:4180`.
- [ ] Smoke test on **one** vhost: `jupyter.cassies.app`. It has no password today (checklist A), so this closes a real hole.
      Use an incognito window: redirect, Kanidm login, back to Jupyter. Jupyter's own token login still sits underneath. Gating it means `passwordHash` can stay empty, or you can set it as a second factor.
      If it fails, debug in this order: `journalctl -u oauth2-proxy`, then `journalctl -u kanidm`, then `curl -sI https://jupyter.cassies.app` (you should get a 302 to `auth.`).
- [ ] Same known rough edge as the source: `rd=` isn't URL-encoded.

### Phase 4: gate the unauthenticated vhosts (`sso = true` in each module)
Several items in hand-off checklist A are fixed here as a side effect.
- [ ] **admins**: `code-cassie-box` (checklist A; keep `auth = "none"` underneath, or add the password too, belt and braces), `victoriametrics`, `vmalert`, `alertmanager`, `vmagent-cassie-box`.
      Note that 8428 is also open on the LAN directly (checklist B, "Firewall"), so gating the vhost doesn't stop anyone going straight to the port. Close the port as well.
- [ ] **household**: `jupyter` (done in phase 3), `filebrowser` (keep `FB_NOAUTH` like the source did; everyone through the portal is its single admin), `homepage`, `silverbullet`, `syncthing`, `calibre`, `changedetection`, `maintainerr`, `boat-ray`, `searxng`, `whoogle`, `redlib`.
- [ ] ***arr** (sonarr, radarr, lidarr, readarr, prowlarr): these are the native nixpkgs servarr modules, so set `services.<arr>.settings.auth.method = "External"` (rendered as `<ARR>__AUTH__METHOD`) instead of container env.
      Set it only while `sso.enable` is on, and only when the module's vhost has `sso = true`. Bypass `/api /feed /ping`; prowlarr gets no `/feed`.
      The homepage widgets call `https://<arr>.cassies.app` with the API key, and recyclarr does too, so `/api` is required.
- [ ] **sabnzbd**: bypass `/api`, `/sabnzbd/api`. **qbittorrent / qbittorrent-lts**: bypass `/api`. The homepage widget and qbtools need it. Both keep their own logins.
- [ ] After each batch, `systemctl --failed`, check the homepage widgets, and check gatus if it's enabled.
      Gatus monitors expect `200`. For gated vhosts they'll now see `302`, so change their conditions or point them at a bypassed `/ping`.

### Phase 5: native OIDC from nix
The mechanics are the same as the source: `mkOidcClient`, secret at `<category>/<app>/oidc-client-secret`.
There's only one host, so the Kanidm client and the app side are in the same module under `mkIf (cfg.enable && config.mySystem.services.kanidm.enable)`.
- [ ] **grafana** (new compared to the source). Set `settings."auth.generic_oauth"` from nix: `client_secret = "$__file{...}"`, `use_pkce = true`, `role_attribute_path = "contains(groups[*], 'admins@idm.cassies.app') && 'Admin' || 'Viewer'"`.
      This also closes the "admin/admin" item in checklist A: set `security.admin_password` from sops as break-glass anyway.
- [ ] **paperless**: as in the source. **Manual once**: connect the existing admin account to Kanidm from the profile page.
- [ ] **immich**: as in the source (admin UI, or `sops.templates` for the config file). Put the mobile redirect `app.immich:///oauth-callback` in `originUrl`. **Manual once**: link the existing account.
- [ ] **romm**: as in the source. `OIDC_REDIRECT_URI=https://romm.cassies.app/api/oauth/openid`. PKCE is relaxed (authlib).
- [ ] **tandoor**: as in the source. Check whether its vhost here is also hand-rolled in a special way.
- [ ] **vikunja** (new). `services.vikunja.settings.auth.openid.providers.kanidm = { authurl = "https://idm.cassies.app/oauth2/openid/vikunja"; clientid = "vikunja"; }`.
      The secret goes through the env file (`VIKUNJA_AUTH_OPENID_PROVIDERS_KANIDM_CLIENTSECRET`). Check that this form works in the packaged version before relying on it.
- [ ] PKCE clean-up, same as the source.

### Phase 6: header auth and UI click-throughs
- [ ] **navidrome**: `ND_REVERSEPROXYUSERHEADER=X-Auth-Request-Preferred-Username`, `ND_REVERSEPROXYWHITELIST=127.0.0.1/32`, with `sso = true` and `ssoBypass` for `/rest` (Subsonic apps) and `/share`.
      Navidrome users must already exist with matching usernames.
- [ ] **linkding**: `LD_ENABLE_AUTH_PROXY=True`, `LD_AUTH_PROXY_USERNAME_HEADER=HTTP_X_AUTH_REQUEST_PREFERRED_USERNAME`, bypass `/api` (browser extension). Create the users once.
- [ ] **calibre-web**: blocked on checklist A ("calibre-web is dead"). After that, add the reverse-proxy header setting in the UI.
- [ ] **jellyfin**: optional, and last. Test the SSO plugin on Cassie's actual TV client before changing anything. The default is to leave it alone.

## 4. Order of work

1. Phase 0. These are hand-off blockers anyway.
2. Phases 1-3 with Jupyter as the only gated app. Nothing else depends on Kanidm yet, so this is low risk.
3. Phase 4, one commit per group (admin tools, household tools, *arr, downloaders). Each is one `sso = true` per module, so each revert is one line.
4. Phase 5: grafana first (it's also a checklist item), then paperless, immich, romm, and the rest.
5. Enrol Cassie (phase 2, manual) **before** anything she uses day to day is gated. Otherwise the first thing she sees at her place is a login page she has no credential for.
6. Phase 6 when convenient. It can happen after the hand-off, since everything is reachable over the tailnet.

**Decided 2026-09-28: SSO lands before shipping.** Phases 0-5 have to be deployed and running for about a week before the box ships. Phase 6 can wait until after the hand-off.

## 5. Headless failure modes (not in the source plan)

- **Kanidm or oauth2-proxy is down** → every gated vhost returns 500. Still reachable: Vaultwarden (never gated), Plex and Jellyfin, SSH and Tailscale.
  To fix it remotely, over SSH: `systemctl status oauth2-proxy kanidm`. The escape hatch is `mySystem.services.sso.enable = false` and a redeploy, which removes every `auth_request` at once.
  Keep that line in the admin page from checklist B ("Stale docs").
- **Alert on it**: once pushover/vmalert work (checklist A), add an alert on `oauth2-proxy.service` / `kanidm.service` failing, and a gatus or blackbox probe on `https://auth.cassies.app/ping` and `https://idm.cassies.app/status`.
- **ACME renewal**: kanidmd doesn't reload certificates, so the ported `reloadServices` entry is required. Otherwise it serves an expired cert about 90 days after the hand-off.
- **Kanidm upgrades under autoupgrade**: nixpkgs drops old `kanidm_1_x` attributes and only supports upgrading one minor version at a time.
  When 1.11 is removed, evaluation fails, and so does the auto-upgrade (it fails safe, but the box stops updating). Bump `kanidm_1_11` → `kanidm_1_12` deliberately, and don't skip a minor version.
- **Backups**: the `online_backup` directory (7 versions) plus restic. To restore: `kanidmd database restore` with the service stopped. Try one restore during the pre-ship test in checklist §E.
- **Time**: WebAuthn and OIDC tokens depend on the clock. NixOS runs timesyncd by default; just confirm it's in sync after the foreign-network test.

## 6. Gotchas carried over from the source
- Kanidm requires PKCE. Use `allowInsecureClientDisablePkce = true` only on the specific client that needs it.
- `originUrl` must match the app's redirect exactly. Mobile `app://` URIs go in the list.
- Group claims are full SPNs (`household@idm.cassies.app`) unless the client uses `preferShortUsername`.
- If a widget breaks after gating, the usual cause is a missing bypass.
- If oauth2-proxy returns 403 after login, the scope map is missing `groups`.
- Provisioning is authoritative. A UI edit to a provisioned client is reverted on the next deploy.
