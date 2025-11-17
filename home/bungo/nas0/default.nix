{
  lib,
  pkgs,
  osconfig,
  ...
}:

# Settings for _user_ on _host_
{
  imports = lib.flatten [
    # ../common/core # Inherit settings shared for _user_ across all hosts
    (map lib.custom.relativeToRoot [
      "home/bungo/common/core"
    ])
  ];

  home = { };
}
