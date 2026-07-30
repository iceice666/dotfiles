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
    "next-milestone/workflows/claude.md"
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

  # Every agent that can discover a personal skill directory gets a symlink
  # farm pointing back at the canonical `.skills/<name>` tree. Add a base here
  # to onboard another agent; SKILL.md itself must stay agent-neutral.
  skillAdapterBases = [
    ".agents/skills" # OMP
    ".claude/skills" # Claude Code
  ];
in
{
  home.file =
    builtins.listToAttrs (map canonicalSkillFile managedSkillFiles)
    // builtins.listToAttrs (
      lib.flatten (map (base: map (skillAdapter base) managedSkills) skillAdapterBases)
    )
    // {
      ".omp/agent/commands/next-milestone.md".source =
        ./agent-skills/skills/next-milestone/workflows/omp.md;
    };

  home.activation.cleanup-managed-skill-links = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for skill in ${lib.concatStringsSep " " managedSkills}; do
      for base in ${
        lib.concatMapStringsSep " " (b: "\"${config.home.homeDirectory}/${b}\"") skillAdapterBases
      }; do
        target="$base/$skill"
        if [ -e "$target" ] && [ ! -L "$target" ]; then
          rm -rf "$target"
        fi
      done
    done
  '';
}
