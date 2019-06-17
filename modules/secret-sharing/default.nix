{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.secretSharing;

  endpointOptions = local: {
    options = {
      ipAddress = mkOption ({
        type = types.str;
        description = "IP address at which the file is served.";
      } // (if local then { default = cfg.default.endpoint.ipAddress; } else {}));

      port = mkOption {
        type = types.int;
        default = cfg.default.endpoint.port;
        description = "Port on which the file is served.";
      };
    };
  };

  securityOptions = {
    options = {
      secretKeyFile = mkOption {
        type = types.str;
        description = ''
          Path to the secret key shared by all the servers.

          The key can be generated with `openssl rand -hex 32`.
        '';
      };
    };
  };

  remoteOptions = {
    options = {
      endpoint = mkOption {
        type = types.submodule (endpointOptions false);
        description = "Remote server from which the file should be fetched.";
      };

      security = mkOption {
        type = types.submodule securityOptions;
        default = cfg.default.security;
        description = "Security policy to access the file.";
      };

      identifier = mkOption {
        type = types.str;
        description = ''
          Identifier for this file on the remote server.

          This corresponds to the key in the attribute set at
          `secretSharing.sharedFiles`.
        '';
      };

      path = mkOption {
        type = types.str;
        description = "Path to where the file should be fetched.";
      };

      owner = mkOption {
        type = types.str;
        description = "File owner as in chmown(1).";
        default = "root";
        example = "nginx:www-data";
      };

      mode = mkOption {
        type = types.str;
        default = "0600";
        description = "File mode as in chmod(1).";
      };

      wantedBy = mkOption {
        type = with types; listOf str;
        default = [];
        description = "List of systemd units that depends on the file.";
        example = ["nginx.service"];
      };
    };
  };

  sharedOptions = {
    options = {
      endpoint = mkOption {
        type = types.submodule (endpointOptions true);
        default = cfg.default.endpoint;
        description = "Endpoint on which the file is served.";
      };

      security = mkOption {
        type = types.submodule securityOptions;
        default = cfg.default.security;
        description = "Security policy to access the file.";
      };

      path = mkOption {
        type = with types; nullOr str;
        default = null;
        description = "Path of the file to be served.";
      };

      command = mkOption {
        type = with types; nullOr str;
        default = null;
        description = "Command whose output is going to be shared.";
      };

      salt = mkOption {
        type = types.str;
        default = cfg.default.salt;
        description = "Salt to generate initialisation vector.";
      };
    };
  };

  sharedFiles = attrValues (mapAttrs (identifier: file:
    file // { inherit identifier; }
  ) cfg.sharedFiles);

  groupedSharedFiles =
    groupBy (f: "${f.endpoint.ipAddress}:${toString f.endpoint.port}") sharedFiles;

  encryptScript = with pkgs; runCommand "encrypt-file" { buildInputs = [makeWrapper]; } ''
    makeWrapper ${./encrypt-file.sh} "$out" \
      --suffix PATH : "${lib.makeBinPath [coreutils openssl]}"
  '';

  fetchScript = with pkgs; runCommand "fetch-file" { buildInputs = [makeWrapper]; } ''
    makeWrapper ${./fetch-file.sh} "$out" \
      --suffix PATH : "${lib.makeBinPath [coreutils curl openssl]}"
  '';

in
{
  options.secretSharing = {
    remoteFiles = mkOption {
      type = with types; listOf (submodule remoteOptions);
      default = [];
      description = "Files to be fetched from remote servers.";
    };

    sharedFiles = mkOption {
      type = with types; attrsOf (submodule sharedOptions);
      default = {};
      description = "Files to share with remote servers indexed by identifier.";
    };

    default = mkOption {
      type = types.submodule {
        options = {
          security = mkOption {
            type = types.submodule securityOptions;
            default = {};
            description = "Default security policy if not specified otherwise.";
          };

          salt = mkOption {
            type = types.str;
            default = config.networking.hostName;
            description = "Salt used to generate initialisation vectors based on identifiers.";
          };

          endpoint = mkOption {
            type = types.submodule {
              options = {
                ipAddress = mkOption {
                  type = types.str;
                  default = "0.0.0.0";
                  description = "Default IP address on which to listen for requests.";
                };

                port = mkOption {
                  type = types.int;
                  default = 23879;
                  description = "Default port used to share or fetch files.";
                };
              };
            };
            default = {};
          };
        };
      };
      description = "Default values for all shared and remote files.";
      default = {};
    };
  };

  config = {
    assertions = builtins.concatLists (map (file: [
      {
        assertion = builtins.match "^[[:alnum:]_-]+$" file.identifier != null;
        message = ''
          Invalid characters in identifier for shared file:
          secretSharing.sharedFiles.\"${file.identifier}\".
        '';
      }
      {
        assertion = (file.path != null) != (file.command != null);
        message = ''
          Either path or command must be set in
          secretSharing.sharedFiles.\"${file.identifier}\".
        '';
      }
    ]) sharedFiles);

    services.nginx = mkIf (sharedFiles != []) {
      enable = true;
      virtualHosts = builtins.mapAttrs (_: files:
        let
          firstFile = builtins.head files; # It can't be empty.
        in
        {
          listen = singleton {
            addr = firstFile.endpoint.ipAddress;
            port = firstFile.endpoint.port;
          };
          serverName = "secret.sharing.nixos";
          locations = builtins.listToAttrs (map (file:
            let
              sharedType = if file.path != null then "path" else "command";
              sharedObject = if file.path != null then file.path else file.command;
            in
            {
              name = "= /${file.identifier}";
              value = {
                extraConfig = ''
                  fastcgi_pass unix:${config.services.fcgiwrap.socketAddress};
                  fastcgi_param SCRIPT_FILENAME ${encryptScript};
                  fastcgi_param IDENTIFIER ${file.identifier};
                  fastcgi_param SALT ${file.salt};
                  fastcgi_param SHARED_TYPE ${sharedType};
                  fastcgi_param SHARED_OBJECT ${pkgs.lib.strings.escapeNixString sharedObject};
                  fastcgi_param SECRET_KEY_FILE ${file.security.secretKeyFile};
                '';
              };
            }) files);
        }
      ) groupedSharedFiles;
    };

    services.fcgiwrap = mkIf (sharedFiles != []) {
      enable = true;
    };

    systemd.services = builtins.listToAttrs (map (file: {
      name = "fetch${pkgs.lib.strings.replaceStrings ["/"] ["-"] file.path}";
      value = {
        description = ''
          Fetch ${file.path} from remote server (see secretSharing.remoteFiles).
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        inherit (file) wantedBy;
        before = file.wantedBy;
        script = ''
          ${fetchScript} ${pkgs.lib.strings.escapeShellArgs (with file; [
            file.endpoint.ipAddress
            file.endpoint.port
            file.identifier
            file.security.secretKeyFile
            file.path
            file.owner
            file.mode
          ])}
        '';
      };
    }) cfg.remoteFiles);
  };
}
