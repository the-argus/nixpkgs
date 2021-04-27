{ lib, stdenv, writeScript, fetchurl, requireFile, unzip, clang_10, lld_10, mono, which,
  xorg, xdg-user-dirs, vulkan-loader, libpulseaudio, udev }:

let
  deps = import ./cdn-deps.nix { inherit fetchurl; };
  linkDeps = writeScript "link-deps.sh" (lib.concatMapStringsSep "\n" (hash:
    let prefix = lib.concatStrings (lib.take 2 (lib.stringToCharacters hash)); # TODO: Use UE4_GITDEPS instead
    in ''
      mkdir -p .git/ue4-gitdeps/${prefix}
      ln -s ${lib.getAttr hash deps} .git/ue4-gitdeps/${prefix}/${hash}
    ''
  ) (lib.attrNames deps));
  libPath = lib.makeLibraryPath [
    xorg.libX11 xorg.libXScrnSaver xorg.libXau xorg.libXcursor xorg.libXext
    xorg.libXfixes xorg.libXi xorg.libXrandr xorg.libXrender xorg.libXxf86vm
    xorg.libxcb vulkan-loader libpulseaudio stdenv.cc.cc.lib udev
  ];
in
stdenv.mkDerivation rec {
  pname = "ue4";
  version = "4.26.1";
   sourceRoot = "UnrealEngine-${version}-release";
  src = requireFile {
    name = "${sourceRoot}.zip";
    url = "https://github.com/EpicGames/UnrealEngine/releases/tag/${version}-release";
    sha256 = "0nj7h3j68xxvjgli3gz9mrwj28mkm9wfv045fwvpfyffcbk6xs0h";
  };

  UE_USE_SYSTEM_MONO = 1;

  unpackPhase = ''
    ${unzip}/bin/unzip $src
  '';

  patches = [
    ./dont-link-system-stdc++.patch
    ./use-system-compiler.patch
    ./no-unused-result-error.patch
  ];

  configurePhase = ''
    ${linkDeps}

    # Sometimes mono segfaults and things start downloading instead of being
    # deterministic. Let's just fail in that case.
    export http_proxy="nodownloads"

    export HOME="$PWD/home"
    mkdir -p "$HOME"

    export MONO_REGISTRY_PATH="$PWD/mono-registry"
    mkdir -p "$MONO_REGISTRY_PATH"

    patchShebangs Setup.sh
    patchShebangs Engine/Build/BatchFiles/Linux
    ./Setup.sh

    find Engine/Binaries/Linux -type f -executable -exec patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" {} \;
    patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" Engine/Source/ThirdParty/Intel/ISPC/bin/Linux/ispc

    ./GenerateProjectFiles.sh
  '';

  installPhase = ''
    mkdir -p $out/bin $out/share/UnrealEngine

    sharedir="$out/share/UnrealEngine"

    cat << EOF > $out/bin/UE4Editor
    #! $SHELL -e

    sharedir="$sharedir"

    # Can't include spaces, so can't piggy-back off the other Unreal directory.
    workdir="\$HOME/.config/unreal-engine-nix-workdir"
    if [ ! -e "\$workdir" ]; then
      mkdir -p "\$workdir"
      ${xorg.lndir}/bin/lndir "\$sharedir" "\$workdir"
      unlink "\$workdir/Engine/Binaries/Linux/UE4Editor"
      cp "\$sharedir/Engine/Binaries/Linux/UE4Editor" "\$workdir/Engine/Binaries/Linux/UE4Editor"
    fi

    cd "\$workdir/Engine/Binaries/Linux"
    export PATH="${xdg-user-dirs}/bin\''${PATH:+:}\$PATH"
    export LD_LIBRARY_PATH="${libPath}\''${LD_LIBRARY_PATH:+:}\$LD_LIBRARY_PATH"
    exec ./UE4Editor "\$@"
    EOF
    chmod +x $out/bin/UE4Editor

    cp -r . "$sharedir"
  '';
  buildInputs = [ clang_10 lld_10 mono which xdg-user-dirs ];

  # Disable FORTIFY_SOURCE or `SharedPCH.UnrealEd.NonOptimized.ShadowErrors.h` fails to compile
  hardeningDisable = [ "fortify" ];

  meta = {
    description = "A suite of integrated tools for game developers to design and build games, simulations, and visualizations";
    homepage = "https://www.unrealengine.com/what-is-unreal-engine-4";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
    maintainers = [ lib.maintainers.puffnfresh ];
  };
}
