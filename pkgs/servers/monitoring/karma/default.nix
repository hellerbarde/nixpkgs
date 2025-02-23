{ pkgs
, lib
, stdenv
, buildGoModule
, callPackage
, fetchFromGitHub
, nixosTests
, nodejs-18_x
}:

let
  uiNodeDependencies = (import ./node-composition.nix {
    inherit pkgs;
    inherit (stdenv.hostPlatform) system;
    # pin nodejs version
    nodejs = nodejs-18_x;
   }).nodeDependencies;
in

buildGoModule rec {
  pname = "karma";
  version = "0.113";

  src = fetchFromGitHub {
    owner = "prymitive";
    repo = "karma";
    rev = "v${version}";
    hash = "sha256-q0RGdwZQv8ypBcjrf0UjBSp2PlaKzM0wX5q4GzUNX9o=";
  };

  vendorHash = "sha256-8YyTHPIr5Kk7M0LH662KQw4t2CuHZ/3jD0Rzhl8ps0M=";

  nativeBuildInputs = [
    nodejs-18_x
  ];

  postPatch = ''
    # Since we're using node2nix packages, the NODE_INSTALL hook isn't needed in the makefile
    sed -i \
      -e 's/$(NODE_INSTALL)//g' ./ui/Makefile \
      -e 's~NODE_PATH    := $(shell npm bin)~NODE_PATH    := ./node_modules~g' ./ui/Makefile \
      -e 's~NODE_MODULES := $(shell dirname `npm bin`)~NODE_MODULES := ./~g' ./ui/Makefile
  '';

  buildPhase = ''
    # node will fail without this
    export HOME=$(mktemp -d)

    # build requires a writable .cache directory, so we'll create a
    # temporary writable node_modules dir and link every package to it

    # simply linking the node_modules directory would increase the closure size for uiNodeDependencies to >700MB
    cp -r ${uiNodeDependencies}/lib/node_modules ./ui/
    chmod -R +w ./ui/node_modules
    mkdir -p ./ui/node_modules/.bin

    pushd ./ui/node_modules/.bin

    for x in ${uiNodeDependencies}/lib/node_modules/.bin/*; do
      ln -sfv ./$(readlink "$x") ./$(basename "$x")
    done

    popd

    mkdir -p ./ui/node_modules/.cache

    # build package
    VERSION="v${version}" make -j$NIX_BUILD_CORES

    # clean up
    rm -rf ./ui/node_modules
  '';

  installPhase = ''
    install -Dm 755 ./karma $out/bin/karma
  '';

  passthru.tests.karma = nixosTests.karma;

  meta = with lib; {
    description = "Alert dashboard for Prometheus Alertmanager";
    homepage = "https://karma-dashboard.io/";
    license = licenses.asl20;
    maintainers = with maintainers; [ nukaduka ];
  };
}
