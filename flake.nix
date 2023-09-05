{
  description = "Douglas Adams quotes";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let

      # Generate a user-friendly version number.
      version = builtins.substring 0 8 self.lastModifiedDate;

      # System types to support.
      supportedSystems =
        [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in {

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in {
          default = pkgs.buildGoModule {
            pname = "douglas-adams-quotes";
            inherit version;
            src = ./.;
            vendorSha256 = null;
          };
        });

      nixosModules.default = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in { config, lib, pkgs, ... }:

        with lib;
        let
          cfg = config.xe.services.douglas-adams-quotes;
        in {
          options.xe.services.douglas-adams-quotes = {
            enable = mkEnableOption "";

            logLevel = mkOption {
                type = with types; enum [ "DEBUG" "INFO" "ERROR" ];
                example = "DEBUG";
                default = "INFO";
                description = "log level for this application";
            };

            package = mkOption {
              type = types.package;
              default = self.packages.${system}.default;
              description = "rhea package to use";
            };
          };

          config = mkIf cfg.enable {
            systemd.services.douglas-adams-quotes = {
              description = "Douglas Adams quotes";
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                ExecStart = "${cfg.package}/bin/douglas-adams-quotes --log-level=${cfg.logLevel} --addr=:${builtins.toString cfg.port}";
                Restart = "on-failure";
                RestartSec = "5s";
              };
            };
          };
        });

      devShell = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in with pkgs;
        mkShell {
          buildInputs =
            [ go gotools go-tools gopls nixpkgs-fmt ];
        });
    };
}