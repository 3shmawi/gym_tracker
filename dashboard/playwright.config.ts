import { defineConfig, devices } from '@playwright/test';

// End-to-end tests run the built dashboard (vite preview) against a mocked
// Supabase (e2e/fixtures/supabase.ts): no network, no real project, no keys.
// The VITE_ values are placeholders that only satisfy the config check.
const env = {
  VITE_SUPABASE_URL: 'https://abcdefghijklmnopqrst.supabase.co',
  VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_e2e_placeholder_key',
  // Exercise pictures (D2): a placeholder cloud; e2e/fixtures/supabase.ts answers it.
  VITE_CLOUDINARY_CLOUD_NAME: 'azm-e2e',
};

// Locally, a preinstalled Chromium can be used: PW_CHROMIUM=/path/to/chrome.
const executablePath = process.env.PW_CHROMIUM;
const launchOptions = executablePath ? { executablePath } : {};

export default defineConfig({
  testDir: 'e2e',
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: 'http://localhost:4173',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    launchOptions,
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 860 }, launchOptions } },
    { name: 'phone', use: { ...devices['Desktop Chrome'], viewport: { width: 375, height: 812 }, hasTouch: true, launchOptions } },
  ],
  webServer: {
    command: 'npm run build && npm run preview',
    url: 'http://localhost:4173',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    env,
  },
});
