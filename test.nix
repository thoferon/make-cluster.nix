let
  nixpkgsSrc = (import ./sources.nix {}).nixpkgs;

  makeClusterConfig = {
    nodes = {
      hydrogen = {
        vpnIP = "10.128.0.1";
        realIP = "192.168.7.11";
      };

      helium = {
        vpnIP = "10.128.0.2";
        realIP = "192.168.7.12";
      };

      lithium = {
        vpnIP = "10.128.0.3";
        realIP = "192.168.7.13";
      };
    };

    # FIXME: add client and test VPN access
  };

  baseConfigs = import ./lib/make-cluster.nix makeClusterConfig;

  nodes = builtins.mapAttrs (name: module: { pkgs, lib, ... }: {
    imports = [module];
    config = {
      virtualisation.vlans = [7]; # Subnetwork 192.168.7.0/24 on eth1
      networking.interfaces.eth1 = {
        useDHCP = false;
        ipv4.addresses = [{
          address = makeClusterConfig.nodes.${name}.realIP;
          prefixLength = 24;
        }];
      };

      secretSharing.default.security.secretKeyFile =
        lib.mkOverride 1 (toString (pkgs.writeText "not-so-secret-key"
          "16995d092f0e529a42637ac84d6687ef9e42a916e2fc60d25ad39"));
    };
  }) baseConfigs;

in
import (nixpkgsSrc + /nixos/tests/make-test.nix) {
  inherit nodes;

  testScript = ''
    startAll;

    $hydrogen->waitForUnit("default.target");
    $helium->waitForUnit("default.target");
    $lithium->waitForUnit("default.target");

    ${builtins.readFile ./tests/vpn.pl}
  '';
}
