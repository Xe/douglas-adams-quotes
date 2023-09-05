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
    in
    {

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              (final: prev: {
                go = prev.go_1_21;
              })
            ];
          };
        in
        {
          default = pkgs.buildGo121Module {
            pname = "douglas-adams-quotes";
            inherit version;
            src = ./.;
            vendorSha256 = null;
          };
        });

      nixosModules.default = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.xe.services.douglas-adams-quotes;
          in
          {
            options.xe.services.douglas-adams-quotes = {
              enable = mkEnableOption "Enable the Douglas Adams quotes service";

              logLevel = mkOption {
                type = with types; enum [ "DEBUG" "INFO" "ERROR" ];
                example = "DEBUG";
                default = "INFO";
                description = "log level for this application";
              };

              package = mkOption {
                type = types.package;
                default = self.packages.${pkgs.system}.default;
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
          };

      devShells.default = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in with pkgs;
        mkShell {
          buildInputs =
            [ go_1_21 gotools go-tools gopls nixpkgs-fmt ];
        });

      checks.x86_64-linux = let
        pkgs = nixpkgs.legacyPackages.x86_64-linux; 
        in {
          basic = pkgs.nixosTest({
            name = "douglas-adams-quotes";
            nodes.default = { config, pkgs, ... }: {
              imports = [ self.nixosModules.default ];
              xe.services.douglas-adams-quotes.enable = true;
            };
            testScript = ''
              start_all()

              default.wait_for_unit("douglas-adams-quotes.service")
              print(default.wait_until_succeeds(
                "curl -s http://localhost:8080/quote.json"
              ))
            '';
          });
        };
    };
}
