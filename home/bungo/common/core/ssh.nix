{
  pkgs,
  ...
}:
{
  programs.ssh = {
    enable = true;

    matchBlocks = {
      "git" = {
        host = "gitlab.com github.com";
        user = "git";
        identitiesOnly = true;
        identityFile = "~/.ssh/id_ed25519";
      };
    };
  };
}
