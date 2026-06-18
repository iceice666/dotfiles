{
  config,
  dotfiles,
  homolab,
  pkgs,
  ...
}:

let
  ketchBrowser =
    if pkgs.stdenv.hostPlatform.isLinux then
      "${pkgs.chromium}/bin/chromium"
    else
      "/Applications/Chromium.app/Contents/MacOS/Chromium";
in
{
  sops.secrets.ketch_exa_api_key = {
    sopsFile = dotfiles + /sensitive/shared/ketch.yaml;
    mode = "0400";
  };

  sops.secrets.cliproxyapi_api_key = {
    sopsFile = dotfiles + /sensitive/shared/cliproxyapi.yaml;
    key = "apiKey";
    mode = "0400";
  };

  sops.templates."pi-models".path = "${config.home.homeDirectory}/.pi/agent/models.json";
  sops.templates."pi-models".mode = "0600";
  sops.templates."pi-models".content = builtins.toJSON {
    providers.cliproxyapi = {
      baseUrl = "${homolab.urls.cliproxyapi}/v1";
      api = "openai-completions";
      apiKey = config.sops.placeholder.cliproxyapi_api_key;
      compat = {
        supportsDeveloperRole = false;
        supportsReasoningEffort = false;
      };
      models = [
        {
          id = "claude-opus-4-8";
          contextWindow = 200000;
          maxTokens = 32000;
        }
        {
          id = "claude-opus-4-7";
          contextWindow = 200000;
          maxTokens = 32000;
        }
        {
          id = "claude-fable-5";
          contextWindow = 200000;
          maxTokens = 32000;
        }
        {
          id = "claude-sonnet-4-6";
          contextWindow = 200000;
          maxTokens = 64000;
        }
        {
          id = "claude-sonnet-4-5-20250929";
          contextWindow = 200000;
          maxTokens = 64000;
        }
        {
          id = "claude-sonnet-4-20250514";
          contextWindow = 200000;
          maxTokens = 64000;
        }
        {
          id = "claude-haiku-4-5-20251001";
          contextWindow = 200000;
          maxTokens = 16000;
        }
        {
          id = "claude-opus-4-20250514";
          contextWindow = 200000;
          maxTokens = 32000;
        }
        {
          id = "claude-opus-4-5-20251101";
          contextWindow = 200000;
          maxTokens = 32000;
        }
        {
          id = "claude-opus-4-1-20250805";
          contextWindow = 200000;
          maxTokens = 32000;
        }
        {
          id = "claude-opus-4-6";
          contextWindow = 200000;
          maxTokens = 32000;
        }
        {
          id = "claude-opus-4-6-thinking";
          contextWindow = 200000;
          maxTokens = 32000;
          reasoning = true;
        }
        {
          id = "claude-3-7-sonnet-20250219";
          contextWindow = 200000;
          maxTokens = 64000;
          reasoning = true;
        }
        {
          id = "claude-3-5-haiku-20241022";
          contextWindow = 200000;
          maxTokens = 8192;
        }
        {
          id = "gpt-5.5";
          contextWindow = 128000;
          maxTokens = 16384;
        }
        {
          id = "gpt-5.4";
          contextWindow = 128000;
          maxTokens = 16384;
        }
        {
          id = "gpt-5.4-mini";
          contextWindow = 128000;
          maxTokens = 16384;
        }
        {
          id = "gpt-5.3-codex-spark";
          contextWindow = 128000;
          maxTokens = 16384;
        }
        {
          id = "gpt-oss-120b-medium";
          contextWindow = 128000;
          maxTokens = 16384;
        }
        {
          id = "gemini-3-pro-high";
          contextWindow = 1000000;
          maxTokens = 8192;
        }
        {
          id = "gemini-3-pro-low";
          contextWindow = 1000000;
          maxTokens = 8192;
        }
        {
          id = "gemini-3.1-pro-low";
          contextWindow = 1000000;
          maxTokens = 8192;
        }
        {
          id = "gemini-3-flash";
          contextWindow = 1000000;
          maxTokens = 8192;
        }
        {
          id = "gemini-3.1-flash-image";
          contextWindow = 1000000;
          maxTokens = 8192;
        }
        {
          id = "gemini-3.1-flash-lite";
          contextWindow = 1000000;
          maxTokens = 8192;
        }
        {
          id = "gemini-3.5-flash-low";
          contextWindow = 1000000;
          maxTokens = 8192;
        }
      ];
    };
  };

  home.packages = with pkgs; [
    pi-coding-agent-bin
    ketch
  ];

  sops.templates."ketch-config".path = "${config.home.homeDirectory}/.config/ketch/config.json";
  sops.templates."ketch-config".mode = "0600";
  sops.templates."ketch-config".content = ''
    {
      "backend": "ddg",
      "limit": 5,
      "cache_ttl": "72h",
      "browser": "${ketchBrowser}",
      "brave_api_key": "${config.sops.placeholder.ketch_exa_api_key}",
      "exa_api_key": "${config.sops.placeholder.ketch_exa_api_key}"
    }
  '';

  home.file.".pi/agent/extensions/ketch.ts".text = ''
    import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
    import {
      DEFAULT_MAX_BYTES,
      DEFAULT_MAX_LINES,
      formatSize,
      truncateHead,
    } from "@earendil-works/pi-coding-agent";
    import { StringEnum } from "@earendil-works/pi-ai";
    import { Type } from "typebox";

    const KETCH = "${pkgs.ketch}/bin/ketch";
    const TIMEOUT_MS = 120000;

    type KetchParamValue = boolean | number | string | undefined;

    export default function (pi: ExtensionAPI) {
      function appendOption(args: string[], name: string, value: KetchParamValue) {
        if (value === undefined || value === false) return;
        args.push(name);
        if (value !== true) args.push(String(value));
      }

      async function runKetch(args: string[], signal?: AbortSignal) {
        const result = await pi.exec(KETCH, args, { signal, timeout: TIMEOUT_MS });
        const combined = [result.stdout, result.stderr].filter(Boolean).join("\n");
        const truncation = truncateHead(combined, {
          maxBytes: DEFAULT_MAX_BYTES,
          maxLines: DEFAULT_MAX_LINES,
        });
        let text = truncation.content;
        if (truncation.truncated) {
          text += "\n\n[Output truncated: " + truncation.outputLines + " of " + truncation.totalLines + " lines";
          text += " (" + formatSize(truncation.outputBytes) + " of " + formatSize(truncation.totalBytes) + ").]";
        }
        if (result.code !== 0) {
          throw new Error(text || "ketch exited with code " + result.code);
        }
        return {
          content: [{ type: "text" as const, text }],
          details: { args, code: result.code, truncated: truncation.truncated },
        };
      }

      pi.registerTool({
        name: "ketch_search",
        label: "Ketch Search",
        description: "Search the web with ketch. Returns titles, URLs, and snippets; optionally scrape full page content. Output is truncated to 50KB or 2000 lines.",
        promptSnippet: "Search the web with ketch for current external information.",
        promptGuidelines: [
          "Use ketch_search for web research when repository-local information is insufficient or the user asks for current external information.",
          "Use ketch_scrape to fetch a known URL directly instead of searching for it.",
        ],
        parameters: Type.Object({
          query: Type.String({ description: "Search query" }),
          backend: Type.Optional(StringEnum(["brave", "ddg", "searxng"] as const)),
          limit: Type.Optional(Type.Number({ description: "Maximum number of results" })),
          scrape: Type.Optional(Type.Boolean({ description: "Fetch and extract each search result" })),
          json: Type.Optional(Type.Boolean({ description: "Return ketch JSON output" })),
        }),
        async execute(_toolCallId, params, signal) {
          const args = ["search", params.query];
          appendOption(args, "--backend", params.backend);
          appendOption(args, "--limit", params.limit);
          appendOption(args, "--scrape", params.scrape);
          appendOption(args, "--json", params.json);
          return runKetch(args, signal);
        },
      });

      pi.registerTool({
        name: "ketch_scrape",
        label: "Ketch Scrape",
        description: "Fetch one or more URLs and extract clean markdown. JS-rendered pages use the configured browser when ketch detects a loading shell. Output is truncated to 50KB or 2000 lines.",
        promptSnippet: "Fetch URLs and convert pages to clean markdown with ketch.",
        promptGuidelines: [
          "Use ketch_scrape as the browser/page-fetch tool when the user provides URLs or when ketch_search results need full content.",
        ],
        parameters: Type.Object({
          urls: Type.Array(Type.String({ description: "URL to fetch" }), { minItems: 1 }),
          raw: Type.Optional(Type.Boolean({ description: "Return raw HTML instead of markdown" })),
          noCache: Type.Optional(Type.Boolean({ description: "Bypass ketch page cache" })),
          json: Type.Optional(Type.Boolean({ description: "Return ketch JSON output" })),
        }),
        async execute(_toolCallId, params, signal) {
          const args = ["scrape", ...params.urls];
          appendOption(args, "--raw", params.raw);
          appendOption(args, "--no-cache", params.noCache);
          appendOption(args, "--json", params.json);
          return runKetch(args, signal);
        },
      });

      pi.registerTool({
        name: "ketch_code",
        label: "Ketch Code Search",
        description: "Search real open-source code through Sourcegraph or GitHub Code Search. Output is truncated to 50KB or 2000 lines.",
        promptSnippet: "Search open-source code examples with ketch.",
        promptGuidelines: [
          "Use ketch_code when implementation examples from real open-source repositories would help answer the user.",
        ],
        parameters: Type.Object({
          query: Type.String({ description: "Code search query" }),
          lang: Type.Optional(Type.String({ description: "Language qualifier, for example go, rust, nix, or typescript" })),
          backend: Type.Optional(StringEnum(["sourcegraph", "github"] as const)),
          limit: Type.Optional(Type.Number({ description: "Maximum number of results" })),
          json: Type.Optional(Type.Boolean({ description: "Return ketch JSON output" })),
        }),
        async execute(_toolCallId, params, signal) {
          const args = ["code", params.query];
          appendOption(args, "--lang", params.lang);
          appendOption(args, "--backend", params.backend);
          appendOption(args, "--limit", params.limit);
          appendOption(args, "--json", params.json);
          return runKetch(args, signal);
        },
      });

      pi.registerTool({
        name: "ketch_docs",
        label: "Ketch Docs",
        description: "Search Context7 library/framework docs and snippets. Output is truncated to 50KB or 2000 lines.",
        promptSnippet: "Search library and framework docs with ketch.",
        promptGuidelines: [
          "Use ketch_docs for library or framework API documentation before relying on memory.",
        ],
        parameters: Type.Object({
          query: Type.String({ description: "Documentation query, or library name when resolve is true" }),
          library: Type.Optional(Type.String({ description: "Context7 library ID, for example /charmbracelet/glamour" })),
          resolve: Type.Optional(Type.Boolean({ description: "Resolve matching library IDs instead of fetching docs" })),
          tokens: Type.Optional(Type.Number({ description: "Context7 token budget" })),
          json: Type.Optional(Type.Boolean({ description: "Return ketch JSON output" })),
        }),
        async execute(_toolCallId, params, signal) {
          const args = ["docs", params.query];
          appendOption(args, "--library", params.library);
          appendOption(args, "--resolve", params.resolve);
          appendOption(args, "--tokens", params.tokens);
          appendOption(args, "--json", params.json);
          return runKetch(args, signal);
        },
      });
    }
  '';
}
