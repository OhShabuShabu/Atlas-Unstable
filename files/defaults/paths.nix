{ lib, ... }: {
  scripts = {
    startup = ../bin/shell/startup.sh;
    encrypt = ../bin/encrypted-storage.sh;
    detectHardware = ../bin/shell/detect-hardware.sh;
  };
  assets = {
    plymouth = ../core/config/plymouth/hyprland-mac-style;
    audio = ../audio/startup.mp3;
  };
}
