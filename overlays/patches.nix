# Package fixes that nixpkgs does not carry yet. Drop each entry once the
# pinned nixpkgs ships it.
final: prev: {
  # 1.9.0 (nixpkgs) only matches the host of a redirect_uri against
  # oidc_registration_allowed_redirect_hosts, so Element X Android, whose
  # redirect_uri is the private-use scheme `io.element.android:/`, could not
  # register. 1.9.1 matches schemes too and adds oidc_require_client_approval.
  matrix-tuwunel = prev.matrix-tuwunel.overrideAttrs (
    _:
    let
      version = "1.9.1";
      src = prev.fetchFromGitHub {
        owner = "matrix-construct";
        repo = "tuwunel";
        tag = "v${version}";
        hash = "sha256-MBHChIMNLrP7u8ECRroGiniRGtZGArrpRPfAdkOaOXg=";
      };
    in
    {
      inherit version src;
      cargoDeps = prev.rustPlatform.fetchCargoVendor {
        inherit src;
        hash = "sha256-NDjFv0iKDfkKwOQ3RZ4gO9eQufGf/dmFaGLTcFWH5uw=";
      };
    }
  );
}
