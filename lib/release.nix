# `project-release check|publish <tag>`, siehe release.sh
{
  writeShellApplication,
  git,
  curl,
  jq,
  coreutils,
  findutils,
  name,
  title,
  version,
  branch,
}:
writeShellApplication {
  name = "project-release";
  runtimeInputs = [
    git
    curl
    jq
    coreutils
    findutils
  ];
  runtimeEnv = {
    NAME = name;
    TITLE = title;
    VERSION = version;
    BRANCH = branch;
  };
  text = builtins.readFile ./release.sh;
}
