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
        };
      }
    );
    default = { };
  };
}
