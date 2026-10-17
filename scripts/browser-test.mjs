import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { join, relative, resolve } from "node:path";
import { chromium } from "playwright";

const root = resolve("build/dev/javascript");
const sourceFiles = await readdir("src", { recursive: true });
const publicModules = sourceFiles
  .filter((file) => file.endsWith(".gleam"))
  .map((file) => `/spillway/${file.replace(/\.gleam$/, ".mjs")}`);
const pageErrors = [];

const server = createServer(async (request, response) => {
  const path = new URL(request.url, "http://localhost").pathname;
  if (path === "/") {
    response.setHeader("Content-Type", "text/html");
    response.end("<!doctype html><title>Spillway browser contracts</title>");
    return;
  }
  if (!/^\/(?:[a-z0-9_]+\/)*[a-z0-9_]+\.mjs$/.test(path)) {
    response.writeHead(404).end();
    return;
  }
  try {
    const content = await readFile(join(root, path));
    response.setHeader("Content-Type", "text/javascript");
    response.end(content);
  } catch (error) {
    console.error(`Cannot serve ${relative(root, join(root, path))}:`, error);
    response.writeHead(500).end();
  }
});

let browser;
try {
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  assert(address && typeof address === "object");
  browser = await chromium.launch();
  const page = await browser.newPage();
  page.on("pageerror", (error) => pageErrors.push(error));
  await page.goto(`http://127.0.0.1:${address.port}/`);
  await page.evaluate(async (modules) => {
    // Import source modules individually so an unused root export cannot hide
    // a Node-only dependency. There is no bundler or polyfill in this test.
    for (const module of modules) await import(module);
    const checks = await import("/spillway/protocol_checks.mjs");
    checks.run();
    const examples = await import("/spillway/readme_examples.mjs");
    examples.run();
  }, publicModules);
  assert.deepEqual(pageErrors, []);
  console.log(`Browser contracts passed; imported ${publicModules.length} public modules.`);
} finally {
  await browser?.close();
  await new Promise((resolve, reject) =>
    server.close((error) => error ? reject(error) : resolve()),
  );
}
