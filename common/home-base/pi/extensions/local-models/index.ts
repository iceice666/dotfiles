import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { discoverModels, normalizeServerUrl } from "./discovery.ts";

/** Optional local OpenAI-compatible server (default http://localhost:8080). */
export default async function (pi: ExtensionAPI) {
  const serverUrl = normalizeServerUrl(process.env.PI_LOCAL_MODELS_URL);
  // Pi only refreshes catalogs from the network in some modes, so probe once at
  // load time (startup awaits async factories); a closed port fails immediately.
  const models = process.env.PI_OFFLINE === undefined ? await discoverModels(serverUrl, new AbortController().signal) : [];
  pi.registerProvider("local", {
    name: "Local server",
    baseUrl: `${serverUrl}/v1`,
    // Local servers ignore the key; a value makes the provider count as authenticated.
    apiKey: process.env.PI_LOCAL_MODELS_API_KEY ? "$PI_LOCAL_MODELS_API_KEY" : "local",
    api: "openai-completions",
    models,
    refreshModels: async (context) => (context.allowNetwork ? discoverModels(serverUrl, context.signal) : models),
  });
}
