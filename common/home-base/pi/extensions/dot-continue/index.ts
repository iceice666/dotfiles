import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

export default function (pi: ExtensionAPI) {
  pi.on('input', (event, ctx) => {
    if (
      ctx.mode === 'tui' &&
      event.source === 'interactive' &&
      ctx.isIdle() &&
      event.streamingBehavior === undefined &&
      !event.images?.length &&
      event.text.trim() === '.'
    ) {
      return { action: 'transform', text: 'continue' };
    }
    return { action: 'continue' };
  });
}
