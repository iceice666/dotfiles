import { randomUUID } from "node:crypto";
import { lstatSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve, sep } from "node:path";
import { canonicalPath, inside, type Action } from "./policy.ts";

export interface ScopeGrant { id: string; path: string; kind: "file" | "directory" }
export interface ScopePreview { path: string; kind: "file" | "directory" }
interface StoredGrant { grant: ScopeGrant; originalPath: string }
interface ProtectedRoot { originalPath: string; canonical: string }

function lexicalPath(value: string, cwd: string): string {
  if (typeof value !== "string" || !value || value.includes("\0")) throw new Error("Invalid scope path.");
  let path = value.replace(/^@/, "");
  // resolve() collapses symlink/.. before realpath; do not approve an alternate target.
  if (path.split(sep).includes("..")) throw new Error("Scope path may resolve outside its reviewed boundary; avoid parent traversal.");
  if (path === "~" || path.startsWith("~/")) path = join(homedir(), path.slice(2));
  return resolve(cwd, path);
}

function repositoryRoot(cwd: string): string {
  let candidate = cwd;
  while (true) {
    try {
      const marker = lstatSync(join(candidate, ".git"));
      if (marker.isDirectory() || marker.isFile()) return candidate;
      throw new Error("Repository marker must be an ordinary file or directory.");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    const parent = dirname(candidate);
    if (parent === candidate) throw new Error("File scopes require a Git repository.");
    candidate = parent;
  }
}

function protectedName(path: string): boolean {
  return path.split(sep).some(part => /^(?:\.git|\.pi|\.agents|\.ssh|\.aws|\.gnupg|\.bashrc|\.zshrc|\.profile|AGENTS\.md|SYSTEM\.md)$/i.test(part)
    || /^\.env/i.test(part)
    || /^(?:auth\.json|credentials(?:[._-].*)?|id_(?:rsa|dsa|ed25519|ecdsa)(?:\..*)?|(?:private[-_]?|secret[-_]?)?keys?(?:[._-].*)?)$/i.test(part)
    || /\.(?:pem|key|p12|pfx|jks|keystore)$/i.test(part));
}

/** Session-local file scopes. The caller must obtain human approval before add(). */
export class ScopeStore {
  private readonly cwd: string;
  private readonly originalCwd: string;
  private readonly root: string;
  private readonly originalRoot: string;
  private readonly protectedRoots: ProtectedRoot[];
  private readonly grants = new Map<string, StoredGrant>();
  private generation = 0;

  constructor({ cwd, protectedRoots = [] }: { cwd: string; protectedRoots?: string[] }) {
    this.originalCwd = lexicalPath(cwd, process.cwd());
    this.cwd = canonicalPath(cwd, process.cwd());
    if (!statSync(this.cwd).isDirectory()) throw new Error("Scope working directory must be a directory.");
    this.originalRoot = repositoryRoot(this.originalCwd);
    this.root = canonicalPath(this.originalRoot, this.cwd);
    this.protectedRoots = ["/nix/store", join(homedir(), ".pi"), join(homedir(), ".agents"), join(homedir(), ".config"), ...protectedRoots]
      .map(path => ({ originalPath: lexicalPath(path, this.cwd), canonical: canonicalPath(path, this.cwd) }));
  }

  get revision(): number { return this.generation; }

  private checkRepository(): void {
    if (canonicalPath(this.originalRoot, this.cwd) !== this.root
      || canonicalPath(this.originalCwd, this.cwd) !== this.cwd
      || repositoryRoot(this.originalRoot) !== this.originalRoot) throw new Error("Repository scope changed.");
  }

  private checkPath(original: string, canonical: string): void {
    if (!inside(original, this.originalRoot) || !inside(canonical, this.root)) throw new Error("Scope path is outside the repository.");
    if (protectedName(original) || protectedName(canonical)) throw new Error("Protected paths cannot be covered by file scopes.");
    for (const root of this.protectedRoots) {
      const current = canonicalPath(root.originalPath, this.cwd);
      if ([root.originalPath, root.canonical, current].some(path => inside(original, path) || inside(canonical, path))) {
        throw new Error("Runtime and live control paths cannot be covered by file scopes.");
      }
    }
  }

  preview(path: string): ScopePreview {
    this.checkRepository();
    const original = lexicalPath(path, this.originalCwd);
    const canonical = canonicalPath(path, this.originalCwd);
    this.checkPath(original, canonical);
    const stat = statSync(canonical);
    if (stat.isFile() && stat.nlink === 1) return { path: canonical, kind: "file" };
    if (stat.isDirectory()) return { path: canonical, kind: "directory" };
    throw new Error("Scope must be an existing directory or ordinary, non-hardlinked file.");
  }

  add(path: string): ScopeGrant {
    const preview = this.preview(path);
    const grant: ScopeGrant = { id: randomUUID(), ...preview };
    this.grants.set(grant.id, { grant, originalPath: lexicalPath(path, this.originalCwd) });
    this.generation++;
    return { ...grant };
  }

  list(): ScopeGrant[] { return [...this.grants.values()].map(({ grant }) => ({ ...grant })); }

  revoke(id: string): void {
    if (id === "all") this.grants.clear();
    else this.grants.delete(id);
    this.generation++;
  }

  clear(): void { this.revoke("all"); }

  /** Never overrides policy blocks; caller must evaluate deterministic policy first. */
  match(action: Action): ScopeGrant | undefined {
    try {
      if (!["read", "write", "edit"].includes(action.toolName) || typeof action.input.path !== "string") return undefined;
      this.checkRepository();
      const cwd = lexicalPath(action.cwd, this.originalCwd);
      const canonicalCwd = canonicalPath(action.cwd, this.originalCwd);
      if (!inside(cwd, this.originalRoot) || !inside(canonicalCwd, this.root) || !statSync(canonicalCwd).isDirectory()) return undefined;
      const original = lexicalPath(action.input.path, cwd);
      const canonical = canonicalPath(action.input.path, cwd);
      this.checkPath(original, canonical);
      try {
        const stat = statSync(canonical);
        if (!stat.isFile() || stat.nlink !== 1) return undefined;
      } catch (error) {
        if (action.toolName !== "write" || (error as NodeJS.ErrnoException).code !== "ENOENT") return undefined;
        // Missing targets are only eligible under an existing approved directory.
      }
      for (const { grant, originalPath } of this.grants.values()) {
        const current = this.preview(originalPath);
        if (current.path !== grant.path || current.kind !== grant.kind) continue;
        const matches = grant.kind === "file"
          ? original === originalPath && canonical === grant.path
          : inside(original, originalPath) && inside(canonical, grant.path);
        if (matches) return { ...grant };
      }
    } catch {
      // Filesystem errors, dangling links, and malformed actions never authorize work.
    }
    return undefined;
  }
}
