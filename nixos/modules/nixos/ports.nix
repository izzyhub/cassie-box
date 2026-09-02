{ lib, config, ... }:
with lib;
let
  cfg = config.mySystem.ports;

  # A port is only contended if something else binds it *in the host network
  # namespace*. Container-internal ports don't count: podman gives each
  # container its own netns, which is why browserless, romm and rxresume can
  # all listen on 3000 at once without anyone noticing.
  claimModule = { name, ... }: {
    options = {
      port = mkOption {
        type = types.port;
        description = "Host port bound by this service.";
      };
      protocol = mkOption {
        type = types.enum [ "tcp" "udp" ];
        default = "tcp";
        description = "Transport protocol. tcp/53 and udp/53 are distinct claims.";
      };
      address = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = ''
          Address the service binds. The default means "every interface", which
          conflicts with any other claim on the same port. Narrow it (e.g.
          "127.0.0.1") only when the service really does bind one address.
        '';
      };
      claimedBy = mkOption {
        type = types.str;
        default = name;
        description = "Human-readable owner, used in the conflict message.";
      };
    };
  };

  wildcard = addr: addr == "0.0.0.0" || addr == "::" || addr == "*";

  # Two claims collide when they are the same protocol and port, and their
  # addresses overlap. A wildcard bind overlaps everything - which is exactly
  # the boat-ray case: it bound 0.0.0.0:3000 while homepage held 127.0.0.1:3000.
  collides = a: b:
    a.port == b.port
    && a.protocol == b.protocol
    && (a.address == b.address || wildcard a.address || wildcard b.address);

  claimList = attrValues cfg.claims;

  # Every unordered pair, so each conflict is reported once.
  conflicts = concatLists (imap0
    (i: a: map (b: { inherit a b; }) (filter (b: collides a b) (drop (i + 1) claimList)))
    claimList);

  fmt = c: "${c.claimedBy} (${c.address}:${toString c.port}/${c.protocol})";

  # oci-containers already record their host publishes in the config, so those
  # claims are derived rather than hand-written.
  parsePublish = container: entry:
    let
      proto = if hasSuffix "/udp" entry then "udp" else "tcp";
      body = removeSuffix "/udp" (removeSuffix "/tcp" entry);
      parts = splitString ":" body;
      # "ip:host:container" | "host:container" | "container"
      hostPart = if length parts == 3 then elemAt parts 1
      else if length parts == 2 then head parts
      else null;
      address = if length parts == 3 then head parts else "0.0.0.0";
    in
    # A bare "container" publish gets an ephemeral host port, and ranges
    # ("8000-8010") aren't modelled - skip both rather than guess.
    if hostPart == null || !(all (c: elem c (stringToCharacters "0123456789")) (stringToCharacters hostPart))
    then null
    else {
      name = "oci-${container}-${proto}-${hostPart}";
      value = {
        port = toInt hostPart;
        protocol = proto;
        inherit address;
        claimedBy = "container ${container}";
      };
    };

  derivedContainerClaims = listToAttrs (filter (x: x != null) (concatLists (
    mapAttrsToList (name: c: map (parsePublish name) (c.ports or [ ]))
      config.virtualisation.oci-containers.containers
  )));
in
{
  options.mySystem.ports.claims = mkOption {
    type = types.attrsOf (types.submodule claimModule);
    default = { };
    description = ''
      Registry of host-namespace port bindings, so two enabled services asking
      for the same port fail evaluation instead of crash-looping at runtime.

      Modules register under `mySystem.ports.claims.<app>-<purpose>` inside
      their `mkIf cfg.enable`, so a claim only exists when the service does.
      Ports published by oci-containers are collected automatically.
    '';
    example = literalExpression ''
      {
        boat-ray-http.port = 3001;
        boat-ray-grpc.port = 50051;
      }
    '';
  };

  config = {
    mySystem.ports.claims = derivedContainerClaims;

    assertions = map
      ({ a, b }: {
        assertion = false;
        message = "mySystem.ports: ${fmt a} and ${fmt b} both claim the same host port. Change one of them.";
      })
      conflicts;
  };
}
