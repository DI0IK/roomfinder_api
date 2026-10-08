{ pkgs, lib, config, inputs, ... }:

{
  # Erlang & OTP toolchain
  languages.erlang = {
    enable = true;
    package = pkgs.beam28Packages.erlang;
  };

  # Gleam compiler & CLI
  languages.gleam = {
    enable = true;
  };

  # Additional packages available in the shell
  packages = with pkgs; [
    rebar3 # rebar3 3.27.x
    git
  ];

  env = {
    HEX_OFFLINE = "false";
  };

  enterShell = ''
    gleam --version
    erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
  '';
}