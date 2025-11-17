{
  pkgs,
  ...
}:
{
  programs.btop = {
    enable = true;
    settings = {
      vim_keys = true;
      shown_boxes = "cpu mem net proc gpu0";
    };
  };
}
