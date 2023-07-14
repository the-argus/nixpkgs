{ lib
, stdenv
, callPackage
, cmake
, pkg-config
, qt6
, wayland
, elfutils
, libbfd
}:

stdenv.mkDerivation rec {
  inherit (callPackage ./common.nix { }) version pname src;

  nativeBuildInputs = [
    cmake
    pkg-config
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    wayland
    elfutils
    libbfd
  ] ++ (with qt6; [
    qtbase
    qt5compat
    qtdeclarative
  ]);

  cmakeFlags = [
    "-DQT_VERSION_MAJOR=6"
    "-DGAMMARAY_USE_PCH=OFF"
  ];

  meta = with lib; {
    description = "A software introspection tool for Qt applications developed by KDAB";
    homepage = "https://github.com/KDAB/GammaRay";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
    maintainers = with maintainers; [ rewine ];
  };
}

