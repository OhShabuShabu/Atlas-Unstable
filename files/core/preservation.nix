{
  preservation = {
    enable = true;

    preserveAt."/persistent" = {
      directories = [
        "/etc/nixos"
      ];

      files = [
        {
          file = "/etc/machine-id";
          inInitrd = true;
        }
      ];
    };
  };
}
