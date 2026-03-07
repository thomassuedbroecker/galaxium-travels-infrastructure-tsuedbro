const { test } = require('@playwright/test');

test('inspect MCP Inspector UI', async ({ page }) => {
  const inspectorUrl =
    process.env.INSPECTOR_URL ||
    'http://localhost:6274/?MCP_PROXY_AUTH_TOKEN=local-dev-token';

  await page.goto(inspectorUrl);
  await page.waitForLoadState('networkidle');

  console.log('TITLE', await page.title());
  console.log('URL', page.url());
  console.log('BODY', (await page.locator('body').innerText()).slice(0, 4000));
  console.log('BUTTONS', JSON.stringify(await page.locator('button').allInnerTexts()));
  console.log(
    'FIELDS',
    JSON.stringify(
      await page.locator('input,textarea,select').evaluateAll((nodes) =>
        nodes.map((node) => ({
          tag: node.tagName,
          type: node.type || '',
          placeholder: node.placeholder || '',
          name: node.name || '',
          value: node.value || '',
          ariaLabel: node.getAttribute('aria-label') || '',
        }))
      )
    )
  );
});
