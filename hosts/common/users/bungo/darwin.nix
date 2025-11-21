{
  config,
  lib,
  pkgs,
  ...
}:
{
  # User that system.defaults should apply to
  system.primaryUser = "bungo";

  # Declare macOS user
  users.users.bungo = {
    name = "bungo";
    home = "/Users/bungo";
    shell = pkgs.zsh;
  };

  # macOS defaults
  system.defaults = {
    # Dock settings
    dock = {
      autohide = true;		# Hide Dock
      show-recents = false;	# No recent apps
      tilesize = 42;		# Icon size
      autohide-delay = 0.0;	# Make dock basically impossible to open
      persistent-apps = [
      ];
    };

    # Finder settings
    finder = {
      AppleShowAllExtensions = true;	# Show file extensions
      FXPreferredViewStyle = "Nlsv";	# List view
      ShowPathbar = true;		# Show path bar
      ShowStatusBar = true;		# Show status bar
      QuitMenuItem = true;		# Allow quitting Finder
    };

    # Global macOS settings
    NSGlobalDomain = {
      AppleShowAllExtensions = true;			# Show extensions
      InitialKeyRepeat = 15;				# Delay before key repeat
      KeyRepeat = 2;					# Key repeat speed
      NSAutomaticCapitalizationEnabled = false;		# No auto-capitalization
      NSAutomaticSpellingCorrectionEnabled = false;	# No autocorrect
    };

    # Mouse settings
    ".GlobalPreferences"."com.apple.mouse.scaling" = -1.0; # Disable acceleration

    # Trackpad settings
    trackpad = {
      Clicking = true;			# Tap to click
      TrackpadRightClick = true;	# Two-finger right click
      TrackpadThreeFingerDrag = false;	# Keeping this temporarily until yabai is setup
    };
  };

  # Disable Spotlight indexing (using Raycast instead)
  system.activationScripts.postActivation.text = ''
    mdutil -a -i off &> /dev/null || true
  '';
}
