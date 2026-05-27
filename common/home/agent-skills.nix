{ config, ... }:

let
  managedSkills = [
    "make-commit"
  ];

  managedSkillFiles = [
    "make-commit/SKILL.md"
    "make-commit/agents/openai.yaml"
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
    // builtins.listToAttrs (map (skillAdapter ".codex/skills") managedSkills);
}
