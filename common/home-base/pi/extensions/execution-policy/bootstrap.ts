// Loaded explicitly from the immutable Nix store, never auto-discovered. Pi may
// swallow extension import failures on reload: required enforcement must not.
export default async function mandatoryExecutionPolicy(pi: unknown) {
  try {
    const policy = await import("./index.ts");
    policy.default(pi as Parameters<typeof policy.default>[0]);
  } catch {
    process.stderr.write("Restricted Pi: mandatory execution policy failed to load; refusing to continue.\n");
    process.exit(1);
  }
}
