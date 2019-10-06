{}:
rec {
  nixpkgs = builtins.fetchGit {
    url = "https://github.com/thoferon/nixpkgs.git";
    rev = "7b92c13c2eb7f193604f1a2c058356722364b943";
    ref = "wireguard-publickeyfile";
  };
}
