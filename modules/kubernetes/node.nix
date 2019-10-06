{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.cluster.kubernetes.node;

  caFile = config.services.cfssl.ca;

  certs = import ./certs.nix {
    nodeName = cfg.name;
    ipAddress = cfg.ipAddress;
  };

  inherit (certs) mkCertPath mkCert;

  certificates = builtins.listToAttrs [
    (mkCert {
      name = "kubelet";
      service = "kubelet";
      owner = "kubernetes";
      group = "kubernetes";
      CN = "system:node:${cfg.name}";
      O = "system:nodes";
    })

    (mkCert {
      name = "kube-proxy";
      service = "kube-proxy";
      owner = "kubernetes";
      group = "kubernetes";
      CN = "system:master:${cfg.name}";
      O = "system:masters";
    })

    (mkCert {
      name = "kube-flannel";
      service = "flannel";
      owner = "kubernetes";
      group = "kubernetes";
      CN = "system:node:${cfg.name}";
      O = "system:nodes";
    })
  ];

in
{
  options.services.cluster.kubernetes.node = {
    enable = mkEnableOption "Kubernetes node";

    name = mkOption {
      type = types.str;
      example = "hydrogen";
      description = "Name of this node.";
    };

    ipAddress = mkOption {
      type = types.str;
      example = "10.128.0.1";
      description = "IP address of this address in the VPN.";
    };

    masterIPAddress = mkOption {
      type = types.str;
      example = "10.128.0.1";
      description = "IP Address of one of the API servers.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.kubectl];

    services.kubernetes = {
      roles = ["node"];
      easyCerts = false;
      inherit caFile;

      kubeconfig = {
        inherit caFile;
        certFile = mkCertPath "kubelet";
        keyFile = mkCertPath "kubelet-key";
        server = "https://${cfg.masterIPAddress}:4443";
      };

      apiserverAddress = "https://${cfg.masterIPAddress}:4443";

      kubelet = {
        address = cfg.ipAddress;
        clientCaFile = caFile;
        hostname = cfg.name;
        nodeIp = cfg.ipAddress;
        tlsCertFile = mkCertPath "kubelet";
        tlsKeyFile = mkCertPath "kubelet-key";

        kubeconfig = {
          inherit caFile;
          certFile = mkCertPath "kubelet";
          keyFile = mkCertPath "kubelet-key";
          server = "https://${cfg.masterIPAddress}:4443";
        };
      };

      proxy  = {
        enable = true;
        bindAddress = cfg.ipAddress;

        kubeconfig = {
          inherit caFile;
          certFile = mkCertPath "kube-proxy";
          keyFile = mkCertPath "kube-proxy-key";
          server = "https://${cfg.masterIPAddress}:4443";
        };
      };

      flannel.enable = true;
    };

    services.flannel = {
      iface = config.services.cluster.vpn.interface;

      kubeconfig = config.services.kubernetes.lib.mkKubeConfig "kube-flannel" {
        inherit caFile;
        certFile = mkCertPath "kube-flannel";
        keyFile = mkCertPath "kube-flannel-key";
        server = "https://${cfg.masterIPAddress}:4443";
      };
    };

    networking.firewall.interfaces.${config.services.cluster.vpn.interface} = {
      allowedTCPPorts = [
        10250 # kubelet
      ];
    };

    services.certmgr = {
      enable = true;
      specs = certificates;
    };
  };
}
