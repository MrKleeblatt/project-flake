# `project-forge protect|show`, siehe forge.sh; `cli` ist gh (GitHub) bzw. tea (Codeberg)
{
  writeShellApplication,
  jq,
  cli,
  forge,
  branch,
}:
writeShellApplication {
  name = "project-forge";
  runtimeInputs = [
    jq
    cli
  ];
  runtimeEnv = {
    FORGE = forge;
    BRANCH = branch;
  };
  text = builtins.readFile ./forge.sh;
}
