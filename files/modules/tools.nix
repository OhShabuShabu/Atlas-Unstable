{ pkgs, ... }:

{
  # Core utilities
  home.packages = with pkgs; [
    python3Packages.requests
    yt-dlp
    mpv
  ];
}
