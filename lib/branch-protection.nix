# `branch-protection login|protect|show`, siehe branch-protection.sh; `cli` ist gh (GitHub) bzw.
# tea (Codeberg)
{
  writeShellApplication,
  jq,
  gum,
  cli,
  forge,
  branch,
}:
writeShellApplication {
  name = "branch-protection";
  runtimeInputs = [
    jq
    gum
    cli
  ];
  runtimeEnv = {
    FORGE = forge;
    BRANCH = branch;
  };
  # die deutschen Anführungszeichen in den Texten sind gewollt
  excludeShellChecks = [ "SC1111" ];
  text = builtins.readFile ./branch-protection.sh;
}
