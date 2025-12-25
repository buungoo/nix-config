{
  config,
  lib,
  inputs,
  ...
}:
{
  hostSpec.users = inputs.nix-secrets.nas1.users;
  hostSpec.services = inputs.nix-secrets.nas1.services;
}
