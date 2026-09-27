# Restricted execution

The managed `pi` launcher defaults to a **trusted host control plane with
OS-confined tools**. It is not a sandbox around Pi or its trusted extensions.
Do not load untrusted plugins into that control plane.

## Boundary

- macOS uses Seatbelt (`/usr/bin/sandbox-exec`); Linux uses Nix-pinned bubblewrap
  with user, process and network namespaces and dropped capabilities.
- The original canonical working directory is the workspace. Workers may use
  subdirectories, not widen the workspace. Start a new Pi process to change roots.
- Tools may write workspace files and private scratch. The Nix toolchain is
  read-only. Shell commands cannot access the network, host sockets, home
  credentials, the Nix daemon, or the container daemon.
- File reads/writes/edits/listing, image loading, foreground Bash, user `!`/`!!`,
  background Bash, and todo verification use the same execution-plan module.
  Recursive searches use sandboxed Bash (`rg`, `find`); built-in `grep` and `find`
  are unavailable until their complete subprocess paths have adapters.
- Model calls, public web search, memory, team coordination and session persistence
  remain trusted host operations. Their normal privacy/authorization requirements
  still apply; sandboxing does not prevent sending workspace content to models.
- Missing configuration, missing backend, unsupported platforms, denied operations,
  or bounded safety-scan failures never fall back to unsandboxed execution.

`/sandbox` displays the boundary and its readiness. At session start the footer
shows `sandbox:workspace / offline` only when `boundaryStatus()` finds the pinned
launcher toolchain and backend; otherwise it shows `sandbox:UNAVAILABLE` with an
error notice. Refusal messages state that they are a security boundary and point
to the managed launcher, and Auto Mode uses the same probe to block every
non-coordination tool when the boundary is not attested. There is no off switch, escalation tool, or
approval cache. Auto Mode remains an independent **intent/approval gate**; neither
its `allow` verdict nor `/auto off` expands kernel permissions. A needed download,
SSH/deploy operation, Nix daemon build, or browser action must be performed by the
human outside Pi in this first version.

## Managed launch and compatibility

`common/home-base/pi.nix` installs the wrapper instead of the raw `pi-bin` command.
It pins the toolchain and explicitly loads the repo-owned extension tree from the
Nix store, disables built-in tools and project extension/config loading, and rejects
CLI extension/trust/package overrides. The raw standalone package is still a
normal upstream Pi binary; do not confuse it or SDK embeddings with the managed
entrypoint. The tree is not installed into `~/.pi/agent/extensions/`; that
directory only receives `unmanaged-pi-guard.ts`, which blocks every tool in a Pi
that was not started by the launcher (for example a global npm/Bun install found
earlier on `PATH`). Check `type -a pi` if tools report the launcher missing. Trusted user/global configuration, credentials, and deliberate human
CLI attachments remain host inputs, not agent tool operations. `--tools` is
rejected because upstream Pi lets it reactivate built-in tools; operators can
narrow the managed tool set with `PI_EXECUTION_TOOLS=read,ls` instead.

Project skills/instructions are untrusted prompt data, not executable authority.
Existing unmanaged executable extensions are not loaded by the managed launcher.
The lumo audit also uses the managed launcher, retaining its read/list tool allowlist.
The immutable mandatory bootstrap terminates Pi if enforcement cannot import or
register, including `/reload` where upstream otherwise tolerates extension errors.
A missing/corrupted bootstrap itself is a broken host installation, not a supported
runtime. Deployment does not modify currently running Pi processes; restart after
switching.

## Filesystem caveats

Existing Git/agent control paths are read-only. Common credential-shaped paths
are denied/masked. This is not a secret-content scanner: do not place arbitrary
plaintext secrets inside a workspace you authorize the agent to read.

On Linux, existing sensitive/control paths are masked with mounts; arbitrary new
sensitive names are not dynamically filtered like macOS Seatbelt regex rules.
Project executable-resource loading stays disabled so creating a new `.pi` tree
cannot load it into the trusted host control plane. Do not execute generated
workspace scripts outside the sandbox without reviewing them.

Pre-existing hardlinked regular files and special files are rejected, as are
protected-path symlinks. Workspace inspection is bounded; very large source trees
or package-manager hardlink layouts may require a smaller/copy-based workspace.
The kernel enforces normal symlink access boundaries, but concurrent malicious
host processes changing mounts/inode aliases are outside this design's threat model.
The workspace is a live bind/access grant, not a snapshot or rollback mechanism.

Scratch is per operation and removed at completion. Daemons deliberately escaping
process groups are not a supported workflow; they remain sandbox-confined, but
process-group cleanup is not a guarantee of complete descendant reaping on macOS.

## Development and validation

From `common/home-base/pi`:

```sh
bun test extensions/execution-policy/tests/*.test.ts
bun run test
```

Tests use disposable sentinel files, never real credentials or destructive system
actions. Live Darwin tests require Nix-pinned tools on PATH and verify denied
outside access, environment stripping, network confinement, inherited restrictions
and permitted workspace operations. Linux argv tests are not proof of live kernel
enforcement: run the same adversarial checks on Framework/homolab/lumo before
relying on deployment there. Unsupported user namespaces fail closed.
