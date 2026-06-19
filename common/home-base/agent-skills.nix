{ config, lib, ... }:

let
  managedSkills = [
    "commit"
    "next-milestone"
  ];

  managedSkillFiles = [
    "commit/SKILL.md"
    "commit/agents/openai.yaml"
    "next-milestone/SKILL.md"
    "next-milestone/agents/openai.yaml"
  ];

  canonicalSkillFile = path: {
    name = ".skills/${path}";
    value.source = ./agent-skills/skills/${path};
  };

  skillAdapter = basePath: skill: {
    name = "${basePath}/${skill}";
    value = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.skills/${skill}";
      force = true;
    };
  };
in
{
  home.file =
    builtins.listToAttrs (map canonicalSkillFile managedSkillFiles)
    // builtins.listToAttrs (map (skillAdapter ".agents/skills") managedSkills);

  home.activation.cleanup-managed-skill-links = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for skill in ${lib.concatStringsSep " " managedSkills}; do
      for base in "${config.home.homeDirectory}/.agents/skills"; do
        target="$base/$skill"
        if [ -e "$target" ] && [ ! -L "$target" ]; then
          rm -rf "$target"
        fi
      done
    done
  '';
}
