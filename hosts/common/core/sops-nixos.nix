# NixOS-specific sops configuration
{
  pkgs,
  lib,
  inputs,
  config,
  ...
}:
let
  sopsFolder = builtins.toString inputs.nix-secrets + "/sops";
in
{
  sops = {
    defaultSopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
    validateSopsFiles = false;
    age = {
      # automatically import host SSH keys as age keys
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
    # secrets will be output to /run/secrets
  };

  # For home-manager a separate age key is used to decrypt secrets and must be placed onto the host. This is because
  # the user doesn't have read permission for the ssh service private key. However, we can bootstrap the age key from
  # the secrets decrypted by the host key, which allows home-manager secrets to work without manually copying over
  # the age key.
  sops.secrets = lib.mkMerge [
    # Generate age keys and passwords for each user defined in hostSpec.users
    (lib.mkMerge (
      lib.mapAttrsToList (username: userConfig: {
        # Age key for each user (keep original key name for compatibility)
        "keys/age" = {
          sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
          owner = username;
          group = config.users.users.${username}.group;
          path = "/home/${username}/.config/sops/age/keys.txt";
        };
        # Password for each user
        "passwords/${username}" = {
          sopsFile = "${sopsFolder}/shared.yaml";
          neededForUsers = true;
        };
        # Jellyfin-specific password secrets
        "jellyfin-passwords/${username}" = {
          sopsFile = "${sopsFolder}/shared.yaml";
          owner = "jellyfin";
          group = "jellyfin";
          mode = "0440";
        };
      }) config.hostSpec.users
    ))
    # Cloudflare API credentials
    {
      "cloudflare/api-token" = {
        sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "cloudflare/acme-env" = {
        sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
        owner = "acme";
        group = "acme";
        mode = "0400";
      };
    }
    # Kanidm admin password for provisioning
    {
      "kanidm/admin-password" = {
        sopsFile = "${sopsFolder}/shared.yaml";
        owner = "kanidm";
        group = "kanidm";
        mode = "0400";
      };
    }
    # Immich OIDC client secret
    {
      "immich/oidc-client-secret" = {
        sopsFile = "${sopsFolder}/shared.yaml";
        owner = "root";
        group = "kanidm";
        mode = "0440";
      };
    }
    {
      "oauth2-proxy/oidc-client-secret" = {
        sopsFile = "${sopsFolder}/shared.yaml";
        owner = "kanidm";
        group = "kanidm";
        mode = "0400";
      };
    }
    # ProtonVPN WireGuard configuration
    {
      "protonvpn/wg-config" = {
        sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
        owner = "root";
        group = "root";
        mode = "0644";
      };
    }
    # Recyclarr API keys
    {
      "recyclarr/sonarr-api-key" = {
        sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
        owner = "recyclarr";
        group = "recyclarr";
        mode = "0400";
      };
      "recyclarr/radarr-api-key" = {
        sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
        owner = "recyclarr";
        group = "recyclarr";
        mode = "0400";
      };
    }
    # WireGuard VPN server private key
    {
      "wireguard/private_key" = {
        sopsFile = "${sopsFolder}/${config.hostSpec.hostName}.yaml";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    }
    # step-ca secrets
    {
      "step-ca/intermediate-password" = {
        sopsFile = "${sopsFolder}/shared.yaml";
        owner = "root";
        group = "root";
        mode = "0644";
      };
      "step-ca/oidc-client-secret" = {
        sopsFile = "${sopsFolder}/shared.yaml";
        owner = "root";
        group = "root";
        mode = "0644";
      };
    }
    {
      # step-ca-enroll OIDC secret for enrollment service EnvironmentFile
      "step-ca-enroll/oidc-client-secret" = {
        sopsFile = "${sopsFolder}/shared.yaml";
        owner = "root";
        group = "root";
        mode = "0644";
      };
      # step-ca-enroll OIDC secret for Kanidm basicSecretFile and step-ca
      "step-ca-enroll/oidc-client-secret-raw" = {
        sopsFile = "${sopsFolder}/shared.yaml";
        owner = "root";
        group = "root";
        mode = "0644";
      };
      # step-ca-enroll P12 password for PKCS#12 file encryption
      "step-ca-enroll/p12-password" = {
        sopsFile = "${sopsFolder}/shared.yaml";
        owner = "root";
        group = "root";
        mode = "0644";
      };
    }
  ];

  # The containing folders are created as root and if this is the first ~/.config/ entry,
  # the ownership is busted and home-manager can't target because it can't write into .config...
  # FIXME(sops): We might not need this depending on how https://github.com/Mic92/sops-nix/issues/381 is fixed
  system.activationScripts.sopsSetAgeKeyOwnership = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      username: userConfig:
      let
        ageFolder = "/home/${username}/.config/sops/age";
        user = config.users.users.${username}.name;
        group = config.users.users.${username}.group;
      in
      ''
        mkdir -p ${ageFolder} || true
        chown -R ${user}:${group} /home/${username}/.config
      ''
    ) config.hostSpec.users
  );
}
