{
  lib,
  buildGoModule,
}:

buildGoModule rec {
  pname = "step-ca-enroll";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-UzJFaQ63c5Ruw8Cs3Bci4QuWb3ymaP+vLcLwxlhdYls=";

  meta = with lib; {
    description = "OIDC enrollment service for step-ca client certificates";
    homepage = "https://github.com/yourusername/step-ca-enroll";
    license = licenses.mit;
    maintainers = [ ];
  };
}
