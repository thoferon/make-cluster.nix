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
    allowedIPs = [client.ip];
    persistentKeepalive = true;
    publicKey = client.publicKey;
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
        ip = mkOption {
          type = str;
          description = "IP address of the client in the VPN.";
        };

        publicKey = mkOption {
          type = str;
          description = "Client's public key (see wg pubkey.)";
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

    # FIXME: Should this "logic" be in its own module?
    services.nginx = {
      enable = true;
      virtualHosts.${cfg.realIP} = {
        listen = [{ addr = cfg.realIP; port = 500; }];
        locations."= /wireguard" = {
          tryFiles = "/pubkey =404";
          alias = "/var/wireguard/";
        };
      };
    };

    systemd.services."wireguard-${cfg.interface}-public-keys" = {
      enable = true;
      before = ["wireguard-${cfg.interface}.service"];
      requiredBy = ["wireguard-${cfg.interface}.service"];
      description = "Try to fetch public keys from peers before starting WireGuard.";

      serviceConfig = {
        Type = "oneshot";
        TimeoutSec = 900;
      };

      script = ''
        while [ ! -f "/var/wireguard/$peer.pubkey" ]; do
          for peer in ${concatStringsSep " " (map (peer: peer.realIP) cfg.peers)}; do
            pubkey="$(${pkgs.curl}/bin/curl --fail "http://$peer:500/wireguard" || echo -n)"
            if [ "x$pubkey" != "x" ]; then
              echo "$pubkey" > "/var/wireguard/$peer.pubkey"
            else
              sleep 5
            fi
          done
        done
      '';
    };
  };
}
