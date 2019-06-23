{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.cluster.pki;

in
{
  options.services.cluster.pki = {
    enable = mkEnableOption "PKI";

    initNodeIP = mkOption {
      type = types.str;
      example = "1.2.3.4";
      description = "IP address of the node from which to fetch the CA keys.";
    };

    isInitNode = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to generate the CA keys instead of fetching them.";
    };
  };

  config = mkIf cfg.enable {
    secretSharing.sharedFiles = mkIf cfg.isInitNode {
      pki-ca-pem = {
        path = config.services.cfssl.ca;
      };

      pki-ca-key-pem = {
        path = config.services.cfssl.caKey;
      };
    };

    system.activationScripts.cfssl-init = {
      deps = ["users"];
      text = ''
        mkdir -p "${config.services.cfssl.dataDir}"
        chmod 755 "${config.services.cfssl.dataDir}"
        pushd "${config.services.cfssl.dataDir}"

        ${optionalString cfg.isInitNode ''
        if [ ! -e ca.pem ]; then
          ${pkgs.cfssl}/bin/cfssl genkey -initca - <<-EOF | ${pkgs.cfssl}/bin/cfssljson -bare ca
          {
            "CN": "cluster",
            "hosts": ["cluster.local"],
            "key": {
              "algo": "ecdsa",
              "size": 521
            },
            "names": [
              {
                "L": "Internet"
              }
            ]
          }
        EOF
        fi
        ''}

        chown cfssl:cfssl . ca.csr ca-key.pem ca.pem || true
        popd
      '';
    };

    secretSharing.remoteFiles = mkIf (!cfg.isInitNode) [
      {
        identifier = "pki-ca-pem";
        path = config.services.cfssl.ca;
        endpoint.ipAddress = cfg.initNodeIP;
        owner = "cfssl:cfssl";
        mode = "0644";
        wantedBy = ["cfssl.service"];
      }

      {
        identifier = "pki-ca-key-pem";
        path = config.services.cfssl.caKey;
        endpoint.ipAddress = cfg.initNodeIP;
        owner = "cfssl:cfssl";
        mode = "0600";
        wantedBy = ["cfssl.service"];
      }
    ];

    services.cfssl = {
      enable = true;
    };
  };
}
