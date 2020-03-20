args@{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.cluster.kubernetes.master;

  caFile = config.services.cfssl.ca;
  caKeyFile = config.services.cfssl.caKey;

  certs = import ./certs.nix {
    nodeName = cfg.name;
    ipAddress = cfg.ipAddress;
  };

  inherit (certs) mkCertPath mkCert;

  certificates =
    let
      serviceAccount = mkCert {
        service = "kube-apiserver";
        name = "kube-service-account";
        owner = "kubernetes";
        group = "kubernetes";
      };

      kubeAdmin = mkCert {
        name = "kube-admin";
        service = "kube-apiserver";
        action = "reload"; # Just because it needs to do something
        CN = "cluster-admin";
        O = "system:masters";
      };

      etcd = mkCert {
        name = "etcd";
        service = "etcd";
        owner = "etcd";
        group = "root";
      };

      kubeAPIServer = mkCert {
        name = "kube-apiserver";
        service = "kube-apiserver";
        owner = "kubernetes";
        group = "kubernetes";
        CN = "system:master:${cfg.name}";
        O = "system:masters";
      };

      kubeScheduler = mkCert {
        name = "kube-scheduler";
        service = "kube-scheduler";
        owner = "kubernetes";
        group = "kubernetes";
        CN = "system:master:${cfg.name}";
        O = "system:masters";
      };

      kubeControllerManager = mkCert {
        name = "kube-controller-manager";
        service = "kube-controller-manager";
        owner = "kubernetes";
        group = "kubernetes";
        CN = "system:master:${cfg.name}";
        O = "system:masters";
      };

      kubeAddonManager = mkCert {
        name = "kube-addon-manager";
        service = "kube-addon-manager";
        owner = "kubernetes";
        group = "kubernetes";
        CN = "system:master:${cfg.name}";
        O = "system:masters";
      };

      commonCerts = [
        etcd
        kubeAPIServer
        kubeScheduler
        kubeControllerManager
        kubeAddonManager
      ];

    in
    builtins.listToAttrs
      (if cfg.isInitNode
        then commonCerts ++ [serviceAccount kubeAdmin]
        else commonCerts);

in
{
  options.services.cluster.kubernetes.master = {
    enable = mkEnableOption "Kubernetes master";

    name = mkOption {
      type = types.str;
      example = "hydrogen";
      description = "Name of this node.";
    };

    ipAddress = mkOption {
      type = types.str;
      example = "10.1.0.1";
      description = "IP address of this node in the VPN.";
    };

    masterIPAddresses = mkOption {
      type = with types; attrsOf str;
      example = { hydrogen = "10.1.0.2"; };
      description = "IP addresses of the master nodes.";
    };

    initNode = {
      name = mkOption {
        type = types.str;
        example = "hydrogen";
        description = "Initialisation node's name";
      };

      ipAddress = mkOption {
        type = types.str;
        example = "10.1.0.1";
        description = "Initialisation node's IP address";
      };

      # FIXME: This should go away when the issue with secretSharing not being
      # able to use the VPN is fixed.
      sharedFileIPAddress = mkOption {
        type = types.str;
        example = "1.2.3.4";
        description = "IP address on which secretSharing is listening";
      };
    };

    isInitNode = mkOption {
      type = types.bool;
      default = false;
      description = "Whether this node is the initialisation node.";
    };
  };

  config = mkIf cfg.enable {
    services.kubernetes = {
      roles = ["master"];
      easyCerts = false;
      inherit caFile;

      apiserver = {
        advertiseAddress = cfg.ipAddress;
        bindAddress = cfg.ipAddress;
        securePort = 4443;
        clientCaFile = caFile;
        kubeletClientCaFile = caFile;
        kubeletClientCertFile = mkCertPath "kube-apiserver";
        kubeletClientKeyFile = mkCertPath "kube-apiserver-key";
        proxyClientCertFile = mkCertPath "kube-apiserver";
        proxyClientKeyFile = mkCertPath "kube-apiserver-key";
        tlsCertFile = mkCertPath "kube-apiserver";
        tlsKeyFile = mkCertPath "kube-apiserver-key";
        serviceAccountKeyFile = mkCertPath "kube-service-account-key";

        etcd = {
          inherit caFile;
          servers = ["https://${cfg.ipAddress}:2379"];
          certFile = mkCertPath "kube-apiserver";
          keyFile = mkCertPath "kube-apiserver-key";
        };
      };

      scheduler = {
        enable = true;
        address = cfg.ipAddress;

        kubeconfig = {
          inherit caFile;
          certFile = mkCertPath "kube-scheduler";
          keyFile = mkCertPath "kube-scheduler-key";
          server = "https://${cfg.ipAddress}:4443";
        };
      };

      controllerManager = {
        enable = true;
        bindAddress = cfg.ipAddress;
        rootCaFile = caFile;
        serviceAccountKeyFile = mkCertPath "kube-service-account-key";
        tlsCertFile = mkCertPath "kube-controller-manager";
        tlsKeyFile = mkCertPath "kube-controller-manager-key";

        kubeconfig = {
          inherit caFile;
          certFile = mkCertPath "kube-controller-manager";
          keyFile = mkCertPath "kube-controller-manager-key";
          server = "https://${cfg.ipAddress}:4443";
        };
      };

      addons = {
        dashboard = {
          enable = true;
          rbac = {
            enable = true;
            clusterAdmin = true;
          };
        };

        dns = {
          enable = true;
          replicas = 3;
        };
      };

      addonManager.enable = true;
    };

    services.certmgr = {
      enable = true;
      specs = certificates;
    };

    # FIXME: it is not possible to add new nodes at the moment.
    # The cluster should probably be initialised on the initialisation node
    # with only one node. Other nodes would have `initialClusterState` set
    # to "existing" and a job on the initialisation node could add them to
    # the cluster one at a time waiting for the cluster to be healthy at each
    # step.
    services.etcd = {
      inherit (cfg) name;
      advertiseClientUrls = ["https://${cfg.ipAddress}:2379"];
      certFile = mkCertPath "etcd";
      clientCertAuth = true;
      initialAdvertisePeerUrls = ["https://${cfg.ipAddress}:2380"];
      initialCluster = builtins.attrValues
        (builtins.mapAttrs (name: addr: "${name}=https://${addr}:2380")
          cfg.masterIPAddresses);
      initialClusterState = "new";
      keyFile = mkCertPath "etcd-key";
      listenClientUrls = ["https://${cfg.ipAddress}:2379"];
      listenPeerUrls = ["https://${cfg.ipAddress}:2380"];
      peerCertFile = mkCertPath "etcd";
      peerClientCertAuth = true;
      peerKeyFile = mkCertPath "etcd-key";
      peerTrustedCaFile = caFile;
      trustedCaFile = caFile;
    };

    # Wait for VPN before starting etcd. Systemd's after, requires, etc. didn't
    # work.
    systemd.services.etcd.preStart = ''
      while true; do
        ${pkgs.iproute}/bin/ip \
          address show dev ${config.services.cluster.vpn.interface} \
          && break || sleep 5
      done
    '';

    networking.firewall.interfaces.${config.services.cluster.vpn.interface} = {
      allowedTCPPorts = [
        2379 2380 # etcd
        4443 # apiserver
      ];
    };

    secretSharing.sharedFiles."kube-service-account-key" = mkIf cfg.isInitNode {
      path = "/var/lib/secrets/kube-service-account-key.pem";
    };

    secretSharing.remoteFiles = mkIf (!cfg.isInitNode) [{
      path = "/var/lib/secrets/kube-service-account-key.pem";
      identifier = "kube-service-account-key";
      owner = "kubernetes:kubernetes";
      mode = "0600";
      endpoint.ipAddress = cfg.initNode.sharedFileIPAddress;
      wantedBy = ["kube-apiserver.service"];
    }];
  };
}
