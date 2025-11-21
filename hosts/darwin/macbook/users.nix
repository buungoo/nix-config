{
  config,
  lib,
  inputs,
  ...
}:
{
  hostSpec.users = inputs.nix-secrets.macbook.users;
}
