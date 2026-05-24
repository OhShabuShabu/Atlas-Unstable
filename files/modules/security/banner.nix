{ lib, ... }:
{
  # ============================================================================
  # SECTION 7: SECURITY BANNER
  # ============================================================================
  # INFO: Login banner for legal warning
  environment.etc."issue".text = ''
    *****************************************************************************
    *        WARNING: Authorized Access Only!                                   *
    *        This system is restricted to authorized users only.                 *
    *        All activities on this system are monitored and recorded.           *
    *        Unauthorized access is strictly prohibited and will be prosecuted.  *
    *****************************************************************************
  '';
}
