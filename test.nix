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

    initNode = "hydrogen";

    clients = [
      {
        ipAddress = "10.128.128.1";
        publicKey = "g5hEf9f4q3mr8B1F28BhxzGu5APgFn9aBBqp82LRqmU=";
      }
      {
        ipAddress = "10.128.128.2";
        publicKey = "S6rxaXVv25dSFdhaoVTxs+qnBsmgBmTYdGZK9Pfaiyk=";
      }
    ];
  };

  baseConfigs = import ./lib/make-cluster.nix makeClusterConfig;

  serverNodes = builtins.mapAttrs (name: module: { pkgs, lib, ... }: {
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

  makeClient = realIP: vpnIP: serverRealIP: serverVPNIP: key: { pkgs, lib, ... }: {
    imports = [./modules];
    config = {
      virtualisation.vlans = [7];
      networking.interfaces.eth1 = {
        useDHCP = false;
        ipv4.addresses = [{
          address = realIP;
          prefixLength = 24;
        }];
      };

      networking.wireguard.interfaces.wg0 = {
        ips = [vpnIP];
        privateKey = key;
        peers = pkgs.lib.singleton {
          allowedIPs = ["0.0.0.0/0" "::/0"];
          endpoint = "${serverRealIP}:500";
          publicKeyFile = "/var/wireguard-server.pubkey";
        };
      };

      secretSharing = {
        default.security.secretKeyFile =
          lib.mkOverride 1 (toString (pkgs.writeText "not-so-secret-key"
            "16995d092f0e529a42637ac84d6687ef9e42a916e2fc60d25ad39"));
        remoteFiles = pkgs.lib.singleton {
          endpoint.ipAddress = serverRealIP;
          identifier = "wireguard-public-key";
          path = "/var/wireguard-server.pubkey";
          wantedBy = ["wireguard-wg0.service"];
        };
      };
    };
  };

  clientNodes = {
    alice = makeClient "192.168.7.101" "10.128.128.1" "192.168.7.11" "10.128.0.1"
      "KLv57UEAA1I/xlCTZ6osl4SV6iuVhl9G6uXlGcipoVE=";
    bob = makeClient "192.168.7.102" "10.128.128.2" "192.168.7.11" "10.128.0.2"
      "mEgDDHi7AYhHe3bn82uCRS63XrFFiwD3w6tP4L7CY2I=";
  };

in
import (nixpkgsSrc + /nixos/tests/make-test.nix) {
  nodes = serverNodes // clientNodes;

  testScript = ''
    $hydrogen->start;
    $helium->start;
    $lithium->start;

    $hydrogen->waitForUnit("default.target");
    $helium->waitForUnit("default.target");
    $lithium->waitForUnit("default.target");

    ${builtins.readFile ./tests/vpn.pl}
  '';
}
