{ config
, lib
, ...
}:
{

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # ntfy publish token for the systemd failure hook (system/ntfy-alerts) and the
  # Alertmanager bridge (services/ntfy-alertmanager). Same token as the
  # izzy-nix-config hosts use against huci's ntfy (deny-all).
  # `hooks-env` is an EnvironmentFile (NTFY_TOKEN=...); `hooks-token` is the raw value.
  sops.secrets."services/ntfy/hooks-env".sopsFile = ./secrets.sops.yaml;
  sops.secrets."services/ntfy/hooks-token".sopsFile = ./secrets.sops.yaml;

}
