# Image analysis

`analyze_image` lets a text-only main model ask a configured vision model about a
local image. It does not switch the main model or change its image capability.

```json
{
  "path": "./screenshot.png",
  "question": "請抄出錯誤訊息，並描述它出現的位置。"
}
```

Optional `model` selects an exact `provider/model-id`; the default is
`cliproxyapi-claude/claude-sonnet-5`. The model must exist in Pi's registry and
explicitly declare image input. Missing configuration or authentication fails;
there is no automatic fallback. Authentication is resolved by the model registry
at request time, including the existing SOPS-backed provider key command.

## Limits and trust

- Accepts one local PNG, JPEG, GIF, or WebP up to 5 MiB. Relative paths use the
  session cwd; absolute paths, `~/`, and a leading `@` are supported. Symlinks to
  regular files are allowed. URLs, data URIs, SVG, BMP, and pasted chat attachments
  are not supported. Save attachments to a file first.
- Format detection checks file signatures, not extensions. It is not a full
  decoder: malformed images and provider-specific dimensions/animation limits
  can still be rejected upstream. No resizing or format conversion is performed.
- Sends only a fixed analysis instruction, the question, and the image to the
  selected provider. **Images leave the host and consume model quota.** Do not
  send sensitive images without authorization. No conversation history, local
  file path, tools, or agent skills are sent.
- The provider response is fallible, untrusted evidence. Text embedded in an
  image is not an instruction source. The main model receives text, not pixels,
  and must not claim it directly viewed the image.
- Uses a 120-second deadline, forwards cancellation, disables SDK retries, and
  requests at most 4096 output tokens. Provider/server-side routing is outside
  the extension's control. The output-token limit is reported if reached.
- Analysis text is bounded to 24 KiB / 600 lines, plus a small metadata wrapper.
  If truncated, full received text is saved to a private temporary directory
  (`pi-analyze-image-*`, file mode 0600); its path is returned. These files are
  not automatically removed and may contain sensitive transcriptions.
- Returns model/path/format/size metadata and nested usage for Pi accounting.
  No base64 image or reasoning blocks are put in the tool result. Provider error
  payloads are withheld to avoid leaking credentials or echoed image data.
- This is not a sandbox. It reads files with the invoking user's permissions.
  Cancellation stops waiting and signals the provider; it cannot retract an
  uploaded image or guarantee that remote processing has stopped.

## Development and activation

From the repository root:

```sh
cd common/home-base/pi
bun test extensions/analyze-image/tests/*.test.ts
bun run test
```

Tests use synthetic image data and a fake model registry; no live credentials or
models are used. For a development session, avoid loading a duplicate installed
copy and explicitly load the repo extension:

```sh
pi -e ./common/home-base/pi/extensions/analyze-image/index.ts
```

For managed installation, use the normal host build/switch workflow and reload
or restart Pi. `common/home-base/pi.nix`'s recursive extension links install this directory on
all Pi-enabled hosts without additional Nix wiring. If an unmanaged extension
already uses this directory/name, back it up outside auto-discovery first.

After installation, ask a text-only model to call `analyze_image` on a disposable
non-sensitive screenshot with a known answer. A live provider smoke test is
separate from the offline test suite; declared image capability alone does not
verify CLIProxyAPI's upstream route.
