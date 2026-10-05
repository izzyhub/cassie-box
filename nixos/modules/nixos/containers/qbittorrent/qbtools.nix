{ lib, config, pkgs, ... }:
let
  cfg = config.mySystem.services.qbittorrent;
  image = "ghcr.io/buroa/qbtools:v0.19.14@sha256:905617dfc1a8aa1510381d8e177cc5581a49bfa9d56f3f05e0574f6c83987d3c";
  torrentsFolder = "${config.mySystem.dataFolder}/torrents";

  # Run qbtools inside qbittorrent's network namespace so it reaches the WebUI on
  # localhost, where WebUI\LocalHostAuth=false lets it in without credentials.
  qbtools = { volumes ? [ ], args }: ''
    ${pkgs.podman}/bin/podman run --rm \
      --network container:qbittorrent \
      -v ${config.sops.secrets."services/qbittorrent/config.yaml".path}:/config/config.yaml \
      ${lib.concatMapStringsSep " " (v: "-v ${lib.escapeShellArg v}") volumes} \
      ${image} \
      ${lib.escapeShellArgs args} \
      --server http://localhost \
      --port 8080 \
      --config /config/config.yaml
  '';

  mkJob = startAt: job: {
    script = qbtools job;
    path = [ pkgs.podman ];
    requires = [ "podman-qbittorrent.service" ];
    after = [ "podman-qbittorrent.service" ];
    inherit startAt;
  };
in
with lib;
{
  config = mkIf (cfg.enable && cfg.qbtools) {

    ## Secrets
    sops.secrets."services/qbittorrent/config.yaml" = {
      sopsFile = ./secrets.sops.yaml;
      owner = config.users.users.kah.name;
      inherit (config.users.users.kah) group;
    };

    systemd.services."qbtools-tag" = mkJob "hourly" {
      args = [
        "tagging"
        "--added-on"
        "--expired"
        "--last-activity"
        "--sites"
        "--unregistered"
      ];
    };

    systemd.services."qbtools-prune-orphaned" = mkJob "*-*-* 05:20:00" {
      args = [
        "prune"
        "--exclude-category"
        "manual"
        "--exclude-category"
        "lts"
        "--exclude-category"
        "uploads"
        "--include-tag"
        "unregistered"
      ];
    };

    systemd.services."qbtools-prune-expired" = mkJob "*-*-* 05:10:00" {
      args = [
        "prune"
        "--exclude-category"
        "manual"
        "--exclude-category"
        "uploads"
        "--exclude-category"
        "lts"
        "--include-tag"
        "expired"
        "--exclude-tag"
        "activity:24h"
        "--exclude-tag"
        "permaseed"
        "--exclude-tag"
        "lts"
        "--exclude-tag"
        "site:myanonamouse"
        "--exclude-tag"
        "site:orpheus"
        "--exclude-tag"
        "site:redacted"
        "--exclude-tag"
        "site:beyond-hd"
      ];
    };

    # Deletes anything under qbittorrent's save path that it doesn't own, so the
    # folder must be mounted at the same path qbittorrent reports it at.
    systemd.services."qbtools-orphaned" = mkJob "daily" {
      volumes = [ "${torrentsFolder}:${torrentsFolder}:rw" ];
      args = [
        "orphaned"
        "--exclude-pattern"
        "*_unpackerred"
        "--exclude-pattern"
        "*/manual/*"
        "--exclude-pattern"
        "*/uploads/*"
      ];
    };

  };
}
