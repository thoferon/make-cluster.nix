{ ... }:
{
  imports = [
    ./kubernetes
    ./pki
    ./vpn.nix
    ./secret-sharing
  ];
}
