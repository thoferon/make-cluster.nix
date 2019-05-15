{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.cluster.vpn;

  otherNodes = map (peer: {
    allowedIPs = [peer.vpnIP];
    endpoint = "${peer.realIP}:500";
    publicKeyFile = "/var/wireguard/${peer.realIP}.pubkey";
  }) cfg.peers;

  clients = map (client: {
    inherit (client) publicKey;
    allowedIPs = [client.ipAddress];
    persistentKeepalive = 25;
  }) cfg.clients;

in
{
  options.services.cluster.vpn = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable WireGuard VPN.";
    };

    interface = mkOption {
      type = types.str;
      default = "wg0";
      description = "Interface name to be created.";
    };

    vpnIP = mkOption {
      type = types.str;
      description = "IP address of the node in the VPN.";
    };

    realIP = mkOption {
      type = types.str;
      description = "Physical IP address of the node.";
    };

    peers = mkOption {
      type = with types; listOf (submodule {
        options = {
          realIP = mkOption {
            type = str;
            description = "Physical IP address of the peer.";
          };

          vpnIP = mkOption {
            type = str;
            description = "IP address of the peer in the VPN.";
          };
        };
      });
      default = [];
      description = "Other nodes in the VPN";
    };

    clients = mkOption {
      type = with types; listOf (submodule {
        options = {
          ipAddress = mkOption {
            type = str;
            description = "IP address of the client in the VPN.";
          };

          publicKey = mkOption {
            type = str;
            description = "Client's public key (see wg pubkey.)";
          };
        };
      });
      default = [];
      description = "Clients (not in the cluster) that need to access the VPN.";
    };
  };

  config = mkIf cfg.enable {
    networking.firewall.allowedUDPPorts = [500];
    networking.firewall.allowedTCPPorts = [500];

    networking.wireguard.interfaces.${cfg.interface} = {
      ips = [cfg.vpnIP];
      listenPort = 500;
      privateKeyFile = "/var/wireguard/privkey";
      peers = otherNodes ++ clients;
    };

    networking.nat = mkIf (cfg.clients != []) {
      enable = true;
      internalInterfaces = [cfg.interface];
    };

    system.activationScripts.wireguard = {
      deps = [];
      text = ''
        mkdir -p /var/wireguard
        if [ ! -f /var/wireguard/privkey ]; then
          touch /var/wireguard/privkey
          chmod 600 /var/wireguard/privkey
          ${pkgs.wireguard}/bin/wg genkey > /var/wireguard/privkey
        fi
        ${pkgs.wireguard}/bin/wg pubkey \
          < /var/wireguard/privkey \
          > /var/wireguard/pubkey
        chmod 400 /var/wireguard/privkey
        chmod 644 /var/wireguard/pubkey
      '';
    };

    secretSharing = {
      sharedFiles."wireguard-public-key" = {
        path = "/var/wireguard/pubkey";
        endpoint.ipAddress = cfg.realIP;
      };

      remoteFiles = map (peer: {
        identifier = "wireguard-public-key";
        endpoint.ipAddress = peer.realIP;
        path = "/var/wireguard/${peer.realIP}.pubkey";
        mode = "0440";
        wantedBy = ["wireguard-${cfg.interface}.service"];
      }) cfg.peers;
    };
  };
}
