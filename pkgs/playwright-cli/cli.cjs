#!/usr/bin/env node
// Keep upstream's CLI and daemon lifecycle; disable mutable update checks.
process.env.NO_UPDATE_NOTIFIER = '1';
process.env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = '1';
require('@playwright/cli/playwright-cli.js');
