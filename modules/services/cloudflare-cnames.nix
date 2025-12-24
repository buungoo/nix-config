# Cloudflare CNAME manager - ensures CNAME records exist
{ config, lib, pkgs, ... }:

let
  cfg = config.services.cloudflare-cnames;
in
{
  options.services.cloudflare-cnames = {
    enable = lib.mkEnableOption "Cloudflare CNAME record management";

    apiTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing Cloudflare API token";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Base domain";
    };

    records = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Record name (use '*' for wildcard, '@' for apex)";
          };
          target = lib.mkOption {
            type = lib.types.str;
            description = "CNAME target (use '@' for the base domain)";
          };
          ttl = lib.mkOption {
            type = lib.types.int;
            default = 1; # Auto
            description = "TTL in seconds (1 = Auto)";
          };
        };
      });
      default = [];
      description = "List of CNAME records to manage";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.cloudflare-cnames = {
      description = "Ensure Cloudflare CNAME records exist";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        DynamicUser = true;
      };

      script = ''
        set -euo pipefail

        TOKEN=$(cat ${cfg.apiTokenFile})
        DOMAIN="${cfg.domain}"

        # Extract zone name (last two parts)
        ZONE=$(echo "$DOMAIN" | ${pkgs.gawk}/bin/awk -F. '{print $(NF-1)"."$NF}')

        # Get Zone ID
        ZONE_ID=$(${pkgs.curl}/bin/curl -sf \
          "https://api.cloudflare.com/client/v4/zones?name=$ZONE" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" | ${pkgs.jq}/bin/jq -r '.result[0].id')

        if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
          echo "ERROR: Could not get Zone ID for $ZONE"
          exit 1
        fi

        ensure_cname() {
          local NAME=$1
          local TARGET=$2
          local TTL=$3

          # Convert @ to base domain
          local FULL_NAME="$NAME"
          [ "$NAME" = "@" ] && FULL_NAME="$DOMAIN"
          [ "$NAME" != "@" ] && [ "$NAME" != "*" ] && FULL_NAME="$NAME.$DOMAIN"
          [ "$NAME" = "*" ] && FULL_NAME="*.$DOMAIN"

          local FULL_TARGET="$TARGET"
          [ "$TARGET" = "@" ] && FULL_TARGET="$DOMAIN"

          # Check if record exists
          RECORD=$(${pkgs.curl}/bin/curl -sf \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=CNAME&name=$FULL_NAME" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json")

          RECORD_ID=$(echo "$RECORD" | ${pkgs.jq}/bin/jq -r '.result[0].id')
          CURRENT_TARGET=$(echo "$RECORD" | ${pkgs.jq}/bin/jq -r '.result[0].content')

          if [ "$RECORD_ID" = "null" ]; then
            # Create new record
            echo "Creating CNAME: $FULL_NAME -> $FULL_TARGET"
            ${pkgs.curl}/bin/curl -sf -X POST \
              "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
              -H "Authorization: Bearer $TOKEN" \
              -H "Content-Type: application/json" \
              --data "{\"type\":\"CNAME\",\"name\":\"$FULL_NAME\",\"content\":\"$FULL_TARGET\",\"ttl\":$TTL,\"proxied\":false}" \
              > /dev/null
            echo "✓ Created CNAME: $FULL_NAME -> $FULL_TARGET"
          elif [ "$CURRENT_TARGET" != "$FULL_TARGET" ]; then
            # Update existing record if target changed
            echo "Updating CNAME: $FULL_NAME ($CURRENT_TARGET -> $FULL_TARGET)"
            ${pkgs.curl}/bin/curl -sf -X PUT \
              "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
              -H "Authorization: Bearer $TOKEN" \
              -H "Content-Type: application/json" \
              --data "{\"type\":\"CNAME\",\"name\":\"$FULL_NAME\",\"content\":\"$FULL_TARGET\",\"ttl\":$TTL,\"proxied\":false}" \
              > /dev/null
            echo "✓ Updated CNAME: $FULL_NAME -> $FULL_TARGET"
          else
            echo "✓ CNAME already correct: $FULL_NAME -> $FULL_TARGET"
          fi
        }

        ${lib.concatMapStringsSep "\n" (record: ''
          ensure_cname "${record.name}" "${record.target}" ${toString record.ttl}
        '') cfg.records}

        echo "All CNAME records verified"
      '';
    };
  };
}
