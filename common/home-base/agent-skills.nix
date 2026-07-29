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
    "next-milestone/workflows/omp.md"
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
    // builtins.listToAttrs (map (skillAdapter ".agents/skills") managedSkills)
    // {
      ".omp/agent/commands/next-milestone.md".source =
        ./agent-skills/skills/next-milestone/workflows/omp.md;
    };

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
