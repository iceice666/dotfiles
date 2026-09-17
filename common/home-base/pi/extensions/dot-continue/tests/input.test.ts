import { expect, test } from 'bun:test';
import type { ExtensionAPI, ExtensionContext, InputEvent, InputEventResult } from '@earendil-works/pi-coding-agent';
import extension from '../index';

function input(event: Partial<InputEvent> = {}, context: Partial<ExtensionContext> = {}) {
  let handler: (event: InputEvent, ctx: ExtensionContext) => InputEventResult;
  extension({
    on(name: string, callback: typeof handler) {
      expect(name).toBe('input');
      handler = callback;
    },
  } as ExtensionAPI);
  return handler!(
    { type: 'input', text: '.', source: 'interactive', ...event },
    { mode: 'tui', isIdle: () => true, ...context } as ExtensionContext,
  );
}

test('a standalone dot resumes an idle conversation with an ordinary continue prompt', () => {
  for (const text of ['.', ' . ', '\n.\n']) {
    expect(input({ text })).toEqual({ action: 'transform', text: 'continue' });
  }
  expect(input({ images: [] })).toEqual({ action: 'transform', text: 'continue' });
});

test('ordinary text, paths and punctuation are untouched', () => {
  for (const text of ['', '..', '...', './file', '.config', 'hello.', '。', '`.`']) {
    expect(input({ text })).toEqual({ action: 'continue' });
  }
});

test('busy turns and queued input are untouched', () => {
  expect(input({}, { isIdle: () => false })).toEqual({ action: 'continue' });
  for (const streamingBehavior of ['steer', 'followUp'] as const) {
    expect(input({ streamingBehavior })).toEqual({ action: 'continue' });
  }
});

test('RPC, extension-injected and non-TUI input are untouched', () => {
  for (const source of ['rpc', 'extension'] as const) {
    expect(input({ source })).toEqual({ action: 'continue' });
  }
  for (const mode of ['rpc', 'json', 'print'] as const) {
    expect(input({}, { mode })).toEqual({ action: 'continue' });
  }
});

test('a dot accompanying an image is not a continuation shortcut', () => {
  expect(input({ images: [{ type: 'image', data: 'fixture', mimeType: 'image/png' }] }))
    .toEqual({ action: 'continue' });
});
