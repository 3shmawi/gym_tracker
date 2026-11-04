import preact from '@preact/preset-vite';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [preact()],
  test: {
    environment: 'jsdom',
    include: ['test/**/*.test.{ts,tsx}'],
    // Node 25+ has its own experimental localStorage global, which is empty
    // without --localstorage-file and hides jsdom's (CI's Playwright image
    // runs Node 26). Turn it off so tests use the browser-like one.
    execArgv: ['--no-experimental-webstorage'],
  },
});
