const { defineConfig } = require('@playwright/test');

const port = 8791;

module.exports = defineConfig({
  testDir: 'tests',
  timeout: 60000,
  forbidOnly: !!process.env.CI,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: `http://localhost:${port}`,
    browserName: 'chromium',
    // PW_CHANNEL=chrome runs the installed Chrome rather than the Chromium
    // Playwright downloads.
    channel: process.env.PW_CHANNEL || undefined
  },
  webServer: {
    command: 'node server.js',
    url: `http://localhost:${port}/barcode.html`,
    env: { PORT: String(port) },
    reuseExistingServer: !process.env.CI
  }
});
