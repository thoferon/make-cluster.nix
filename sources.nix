{}:
rec {
  nixpkgs = builtins.fetchGit {
    url = "https://github.com/thoferon/nixpkgs.git";
    rev = "d40823f6efe6af7bd05d25bf29a88c80b51081e1";
    ref = "wireguard-publickeyfile";
  };

  hydrogen = {
    inherit nixpkgs;
  };

  helium = {
    inherit nixpkgs;
  };

  lithium = {
    inherit nixpkgs;
  };
}
