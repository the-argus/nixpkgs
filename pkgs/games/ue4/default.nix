{ lib, stdenv, writeScript, fetchurl, requireFile, unzip, clang_10, lld_10, mono, which,
  xorg, xdg-user-dirs, vulkan-loader, libpulseaudio, udev, libGL, bash, substituteAll }:

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
    xorg.libxcb vulkan-loader libpulseaudio stdenv.cc.cc.lib udev libGL
  ];
in
stdenv.mkDerivation rec {
  pname = "ue4";
  version = "4.26.2";
   sourceRoot = "UnrealEngine-${version}-release";
  src = requireFile {
    name = "${sourceRoot}.zip";
    url = "https://github.com/EpicGames/UnrealEngine/releases/tag/${version}-release";
    sha256 = "18w3kxfwjqkjhx4ssf6jy47xjsvixyhma7mxap430radq96gad5g";
  };

  UE_USE_SYSTEM_MONO = 1;

  unpackPhase = ''
    ${unzip}/bin/unzip $src
  '';

  patches = [
    ./dont-link-system-stdc++.patch
    ./use-system-compiler.patch
    ./no-unused-result-error.patch
    (substituteAll {
      src = ./fix-paths.patch;
      bash = "${bash}/bin/bash";
    })
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

    # Indicate that this is an "installed" build of the engine.
    # This will cause `FPaths::EngineUserDir` to return a different
    # directory that belongs to the current user and is guaranteed
    # to be writable.
    touch $sharedir/Engine/Build/InstalledBuild.txt
  '';
  buildInputs = [ clang_10 lld_10 mono which xdg-user-dirs ];

  outputs = [ "out" "debug" ];

  postFixup = ''
    # UE4's build process automatically separates debug information. We just
    # have to move it to a separate output.
    pushd "$out"
    while IFS= read -r -d $'\0' i; do
      # Extract the Build ID. FIXME: there's probably a cleaner way.
      id="$($READELF -n "$i" | sed 's/.*Build ID: \([0-9a-f]*\).*/\1/; t; d')"
      if [ "''${#id}" -lt 2 ]; then
        echo "could not find build ID of $i, skipping" >&2
        continue
      fi

      # The `.build-id` directory, wherein GDB searches for debug info
      i_dst1="$debug/lib/debug/.build-id/''${id:0:2}/''${id:2}.debug"

      # Put another copy preserving the original directory structure just in
      # case. (Putting all of them in a `$debug/lib/debug` will cause file name
      # collisions because other platforms' precompiled binaries are present in $out)
      i_dst2="$debug/$i"

      mkdir -p "`dirname "$i_dst1"`"
      mkdir -p "`dirname "$i_dst2"`"
      mv "$i" "$i_dst1"
      ln -sf "$i_dst1" "$i_dst2"
    done < <(find . -type f -iname '*.debug' -print0)
    popd
  '';

  # Disable FORTIFY_SOURCE or `SharedPCH.UnrealEd.NonOptimized.ShadowErrors.h` fails to compile
  hardeningDisable = [ "fortify" ];

  meta = {
    description = "A suite of integrated tools for game developers to design and build games, simulations, and visualizations";
    homepage = "https://www.unrealengine.com/what-is-unreal-engine-4";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
    maintainers = [ ];
    # See issue https://github.com/NixOS/nixpkgs/issues/17162
  };
}
