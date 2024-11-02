{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShell."${system}" = pkgs.mkShell {
        packages = with pkgs; [ zola ];
      };

      packages."${system}".default = pkgs.stdenv.mkDerivation {
        inherit system;
        name = "mhu-dev";
        src = pkgs.lib.cleanSource ./.;
        buildPhase = ''
          ${pkgs.zola}/bin/zola build --output-dir "$out"
        '';
      };
    };
}
