# Interface module: declares custom.kanidm.oauthClients
# Consumed by kanidm.nix which maps these into provision.systems.oauth2
#
# Services declare their own OAuth clients:
#   custom.kanidm.oauthClients.myservice = {
#     displayName = "My Service";
#     originUrl = "https://myservice.example.com/callback";
#     originLanding = "https://myservice.example.com/";
#     secretFile = config.sops.secrets."myservice/oidc-secret".path;
#     scopeMap.myservice_users = [ "openid" "email" "profile" ];
#   };
{ lib, ... }:
{
  options.custom.kanidm.oauthClients = lib.mkOption {
    description = "OAuth2 client registrations for Kanidm";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          displayName = lib.mkOption {
            type = lib.types.str;
            description = "Display name for the OAuth2 client";
          };
          originUrl = lib.mkOption {
            type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
            description = "OAuth2 origin/redirect URLs";
          };
          originLanding = lib.mkOption {
            type = lib.types.str;
            description = "Landing page URL after authentication";
          };
          public = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Create a public OAuth2 client (no secret, PKCE-only, allows http://localhost redirects). For native/mobile apps.";
          };
          secretFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Path to the file containing the client secret. Required for confidential clients, must be null for public clients.";
          };
          enableLegacyCrypto = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable legacy crypto (RS256 instead of ES256)";
          };
          allowInsecureClientDisablePkce = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Disable PKCE on this OAuth2 client. Required for clients that
              do not support sending a code_challenge (e.g., Planka v2.1.1).
              Only safe for confidential clients (those with a client secret).
            '';
          };
          preferShortUsername = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Prefer short usernames in tokens";
          };
          scopeMap = lib.mkOption {
            type = lib.types.attrsOf (lib.types.listOf lib.types.str);
            default = { };
            description = "Scope maps: group name -> list of scopes";
          };
          claimMap = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  joinType = lib.mkOption {
                    type = lib.types.enum [
                      "array"
                      "csv"
                      "ssv"
                    ];
                    default = "array";
                    description = "How multiple values are joined into the claim";
                  };
                  valuesByGroup = lib.mkOption {
                    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
                    default = { };
                    description = "Kanidm group name -> claim values to emit for members of that group";
                  };
                };
              }
            );
            default = { };
            description = ''
              Custom OIDC claims emitted in the userinfo response based on
              the authenticated user's Kanidm group memberships. Used for
              role-based access where the relying party reads a claim (e.g.,
              `groups`) to decide privilege.
            '';
          };
        };
      }
    );
    default = { };
  };
}
