{ fetchFromGitHub, ... }: rec {
  pname = "gammaray";
  version = "2.11.3";
  src = fetchFromGitHub {
    owner = "KDAB";
    repo = pname;
    rev = "8f2dfd4eb2aa58885f59405c5a247de100c2a41c";
    hash = "sha256-qhhtbNjX/sPMqiTPRW+joUtXL9FF0KjX00XtS+ujDmQ=";
  };
}
