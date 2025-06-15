{ config
, lib
, ...
}:
{

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # Secret for machine-specific pushover
  sops.secrets."services/pushover/env" = {
    sopsFile = ../../modules/nixos/system/pushover/secrets.sops.yaml;
  };
  sops.secrets.pushover-user-key = {
    sopsFile = ../../modules/nixos/system/pushover/secrets.sops.yaml;
  };
  sops.secrets.pushover-api-key = {
    sopsFile = ../../modules/nixos/system/pushover/secrets.sops.yaml;
  };

}
