
export const meta = {
  name: 'update-pkgs',
  description: 'Fetch latest GitHub releases and update pkgs/ Nix derivations',
  phases: [
    { title: 'Scout', detail: 'Check latest GitHub releases for each package' },
    { title: 'Update', detail: 'Compute hashes and patch nix files for outdated packages' },
    { title: 'Direct', detail: 'Re-hash packages with no versioned releases' },
  ],
}

const REPO = '/Users/iceice666/dotfiles'

const PACKAGES = [
  { name: 'codex-cli-bin',       github: 'openai/codex',                tagPrefix: 'rust-v' },
  { name: 'rime-frost',          github: 'gaboolic/rime-frost',          tagPrefix: '' },
  { name: 'zen-bin',             github: 'zen-browser/desktop',          tagPrefix: '' },
  { name: 'utiluti',             github: 'scriptingosx/utiluti',         tagPrefix: 'v' },
  { name: 'ketch',               github: '1broseidon/ketch',             tagPrefix: 'v' },
  { name: 'zed-bin',             github: 'zed-industries/zed',           tagPrefix: 'v' },
  { name: 'pi-coding-agent-bin', github: 'earendil-works/pi',           tagPrefix: 'v' },
  { name: 'default-browser',     github: 'macadmins/default-browser',   tagPrefix: 'v' },
  { name: 'equibop-bin',         github: 'Equicord/Equibop',             tagPrefix: 'v' },
]

const SCOUT_SCHEMA = {
  type: 'object',
  properties: {
    name:           { type: 'string' },
    currentVersion: { type: 'string' },
    latestVersion:  { type: 'string' },
    latestTag:      { type: 'string' },
    needsUpdate:    { type: 'boolean' },
    error:          { type: 'string' },
  },
  required: ['name', 'needsUpdate'],
}

phase('Scout')

const scouts = await parallel(PACKAGES.map(pkg => () =>
  agent(
    `Scout package "${pkg.name}" for version updates.

File to check: ${REPO}/pkgs/${pkg.name}/default.nix
GitHub repo: ${pkg.github}
Tag prefix to strip: "${pkg.tagPrefix}"

Steps:
1. Read ${REPO}/pkgs/${pkg.name}/default.nix and extract the current \`version = "..."\` value.
   If the file does not exist, return needsUpdate=false with an error message.
2. Fetch https://api.github.com/repos/${pkg.github}/releases/latest using WebFetch.
   Parse the "tag_name" field. Strip the prefix "${pkg.tagPrefix}" to get the bare version string.
3. Compare currentVersion with latestVersion. Set needsUpdate=true if they differ.

Return all four fields plus latestTag (full tag_name string).`,
    { label: `scout:${pkg.name}`, phase: 'Scout', schema: SCOUT_SCHEMA }
  )
))

const valid    = scouts.filter(Boolean)
const outdated = valid.filter(s => s.needsUpdate)
const errors   = valid.filter(s => s.error)

log(`Scout complete: ${outdated.length} outdated, ${errors.length} errors`)
log(`Outdated: ${outdated.map(s => `${s.name} (${s.currentVersion} → ${s.latestVersion})`).join(', ') || 'none'}`)

const UPDATE_SCHEMA = {
  type: 'object',
  properties: {
    name:       { type: 'string' },
    success:    { type: 'boolean' },
    oldVersion: { type: 'string' },
    newVersion: { type: 'string' },
    notes:      { type: 'string' },
  },
  required: ['name', 'success', 'oldVersion', 'newVersion'],
}

let updateResults = []

if (outdated.length > 0) {
  phase('Update')

  updateResults = await parallel(outdated.map(scout => () =>
    agent(
      `Update Nix package "${scout.name}" from v${scout.currentVersion} to v${scout.latestVersion}.

Nix file: ${REPO}/pkgs/${scout.name}/default.nix
Old version: ${scout.currentVersion}
New version: ${scout.latestVersion}
New tag: ${scout.latestTag}

HOW TO COMPUTE HASHES (try in order until one succeeds):
  Method A — nix store command:
    nix store prefetch-file --hash-type sha256 --json "<url>" 2>/dev/null
    Parse the "hash" key from JSON output — it is already SRI format (sha256-...).
  Method B — nix-prefetch-url + convert:
    result=$(nix-prefetch-url --type sha256 "<url>" 2>/dev/null) && nix hash to-sri sha256:$result
  Method C — pure curl (flat files only, NOT archives):
    curl -fsSL "<url>" | sha256sum | awk '{print $1}' | python3 -c "import sys,base64,binascii; h=sys.stdin.read().strip(); print('sha256-'+base64.b64encode(binascii.unhexlify(h)).decode())"

FOR fetchFromGitHub (source archives that get unpacked):
  Use Method B with --unpack:
    nix-prefetch-url --unpack --type sha256 "https://github.com/<owner>/<repo>/archive/refs/tags/<tag>.tar.gz" 2>/dev/null | xargs -I{} nix hash to-sri sha256:{}
  Method A also works with --unpack flag:
    nix store prefetch-file --hash-type sha256 --unpack --json "<archive-url>" 2>/dev/null

FOR vendorHash (Go packages):
  This requires a nix build pass. Set vendorHash = lib.fakeHash; temporarily, then run:
    cd ${REPO} && nix build 2>&1 | grep "got:" | awk '{print $2}'
  Or set to "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" as placeholder and note it.

STEPS:
1. Read the nix file carefully. Note every URL pattern and hash field.
2. Replace the version string throughout (version = "${scout.currentVersion}" → "${scout.latestVersion}", and any direct use of old version in URLs).
3. For each URL in the file, build the new URL by substituting the new version/tag, then compute the hash.
4. Edit the file: update version and all hash values. Do NOT change anything else.
5. Return success=true if the file was updated. Include notes for any hash that could not be computed.

Return name="${scout.name}", oldVersion="${scout.currentVersion}", newVersion="${scout.latestVersion}".`,
      { label: `update:${scout.name}`, phase: 'Update', schema: UPDATE_SCHEMA }
    )
  ))
}

// Phase: re-hash the rime-octagram package (tracks master branch, not releases)
phase('Direct')

const DIRECT_SCHEMA = {
  type: 'object',
  properties: {
    name:    { type: 'string' },
    changed: { type: 'boolean' },
    oldHash: { type: 'string' },
    newHash: { type: 'string' },
    notes:   { type: 'string' },
  },
  required: ['name', 'changed'],
}

const octagramResult = await agent(
  `Re-hash the rime-octagram-zh-hant-essay-bgw package which tracks a file on master.

File: ${REPO}/pkgs/rime-octagram-zh-hant-essay-bgw/default.nix
URL: https://media.githubusercontent.com/media/rimeinn/octagram-data/master/models/essay/zh-hant-t-essay-bgw.gram

Steps:
1. Read the file and note the current hash value.
2. Compute the new hash for the URL using one of:
   A) nix store prefetch-file --hash-type sha256 --json "<url>" 2>/dev/null   → parse "hash" key
   B) nix-prefetch-url --type sha256 "<url>" 2>/dev/null | xargs -I{} nix hash to-sri sha256:{}
   C) curl -fsSL "<url>" | sha256sum | awk '{print $1}' | python3 -c "import sys,base64,binascii; h=sys.stdin.read().strip(); print('sha256-'+base64.b64encode(binascii.unhexlify(h)).decode())"
3. If the new hash differs from the stored hash:
   - Update the hash in the file
   - Update the version field to today's date in YYYY-MM-DD format (use the date command: date +%Y-%m-%d)
4. Return changed=true/false, oldHash, newHash.`,
  { label: 'direct:rime-octagram', phase: 'Direct', schema: DIRECT_SCHEMA }
)

// Summarize
const succeeded = updateResults.filter(Boolean).filter(u => u.success)
const failed    = updateResults.filter(Boolean).filter(u => !u.success)

return {
  updated:  succeeded.map(u => ({ name: u.name, from: u.oldVersion, to: u.newVersion, notes: u.notes })),
  failed:   failed.map(u => ({ name: u.name, from: u.oldVersion, to: u.newVersion, notes: u.notes })),
  skipped:  valid.filter(s => !s.needsUpdate).map(s => ({ name: s.name, version: s.currentVersion })),
  errors:   errors.map(s => ({ name: s.name, error: s.error })),
  octagram: octagramResult,
}
