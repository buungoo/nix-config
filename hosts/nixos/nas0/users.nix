{
  config,
  lib,
  inputs,
  ...
}:
{
  hostSpec.users = inputs.nix-secrets.nas0.users;
  hostSpec.services = inputs.nix-secrets.nas0.services;
}
