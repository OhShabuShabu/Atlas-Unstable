{ lib, ... }: {
  gaming = {
    steam = true;
    mangohud = true;
    gamescope = true;
  };
  development = {
    neovim = true;
    git = true;
  };
  security = {
    fail2ban = true;
    clamav = true;
  };
}
