import { buildSessionContext, type SessionEntry } from "@earendil-works/pi-coding-agent";

export const MAX_CONTEXT_CHARS = 48000;

// Flatten tool exchanges so a snapshot taken mid-tool-call is still a valid request.
// Thinking, images, tool details and UI-only custom entries are deliberately omitted.
export function conversationSnapshot(entries: SessionEntry[], limit = MAX_CONTEXT_CHARS): string {
  const messages = buildSessionContext(entries).messages;
  const sections = messages.map(message => {
    if (message.role === "bashExecution") {
      return message.excludeFromContext ? "" : `Bash: ${message.command}\n${message.output}`;
    }
    if (message.role === "compactionSummary" || message.role === "branchSummary") {
      return `Summary: ${message.summary}`;
    }
    const content = message.content;
    const text = typeof content === "string" ? content : content.map(part => {
      if (part.type === "text") return part.text;
      if (part.type === "toolCall") return `Tool call: ${part.name} ${JSON.stringify(part.arguments)}`;
      return "";
    }).filter(Boolean).join("\n");
    return text ? `${message.role}: ${text}` : "";
  }).filter(Boolean).join("\n\n");
  return sections.length > limit
    ? `[Earlier context omitted; recent snapshot only]\n${sections.slice(-limit)}`
    : sections;
}
