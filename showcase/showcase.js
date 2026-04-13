#!/usr/bin/env node

const { chromium } = require("playwright");
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const readline = require("readline");

// Config
const BASE_URL = process.env.TUNNELD_URL || "http://localhost:4000";
const LOGIN_USER = process.env.TUNNELD_USER || "admin";
const LOGIN_PASS = process.env.TUNNELD_PASS || "admin";
const OUTPUT_DIR = path.join(__dirname, "output");
const VIEWPORT = { width: 1440, height: 900 };
const MAX_TURNS = 15;

// App Knowledge (baked in from codebase)
const APP_CONTEXT = `
You are controlling a browser to take screenshots of "Tunneld" — a wireless-first, zero-trust programmable gateway for single-board computers (Raspberry Pi, NanoPi). It runs Elixir/Phoenix LiveView.

The app is running in MOCK_DATA mode with fake but realistic data.

## Routes
- / — Login page (username + password form)
- /setup — First-run setup wizard (WiFi → Zrok, 2 steps)
- /dashboard — Main dashboard (requires login)

## Login
- Form fields: input name="form[name]", input name="form[password]"
- Submit button is the form submit
- After login, redirects to /dashboard

## Dashboard Layout
Top bar has 3 buttons:
- "Configure Network" (opens Zrok/overlay sidebar)
- "Internet Access" (opens WiFi sidebar)
- Settings gear icon (dropdown: Authentication, Restart Device)

Main content sections (top to bottom):
1. Welcome banner — version info, "Update Now" button
2. System Resources — CPU, Memory, Storage gauge charts
3. Services — dnsmasq, dhcpcd, dnscrypt-proxy, nginx (status dots green/red)
4. Resources — public/private tunneled services cards with toggle switches
5. Devices — connected network devices with hostname, IP, MAC

## Sidebar (right overlay, 35% width)
Opened by clicking dashboard buttons. Types:
- "wlan" — WiFi config: connected network, scan button, SQM bandwidth modes
- "zrok" — Overlay network: control plane URL, environment status, connect/disconnect
- "resource" — Individual resource details
- "service" — Service logs, restart button
- "authentication" — Reset login, WebAuthn setup, download Root CA

Close sidebar: click the X button or the overlay backdrop.

## Modals
- Triggered by various actions (add resource, connect WiFi, confirm delete)
- Have a title, description, form fields, and action buttons
- Close: X button top-right or backdrop click

## Key Selectors
- Logout: button/div with phx-click="logout"
- WiFi panel: element with text "Internet Access"
- Zrok panel: element with text "Configure Network"
- Settings menu: cog/gear icon button
- Add Resource: button with text "Add Resource"
- Close sidebar: X icon with phx-click="close_details"
- Modal close: X icon with phx-click="modal_close"
- Services: cards in #services section
- Devices: cards in #devices section
- Resources: cards in #resources section
- System resources: gauges in #system_resources section
- Welcome: #welcome section

## Visual Style
Dark theme. Primary dark background with lighter secondary panels.
Green dots = healthy/running. Red dots = stopped/error.
Cards have rounded corners, subtle borders.

## Important Notes
- This is Phoenix LiveView — page transitions are SPA-style, no full reloads
- After clicking something, wait for the UI to settle (animations, data loading)
- Screenshots should capture the feature clearly — crop to relevant area when possible
- Take multiple screenshots showing different states (before/after, expanded/collapsed)
- The app uses Tailwind CSS classes
`;

const TWEET_STYLE = `
## Tweet Style Guide for @tunneld posts

Tone: Professional but approachable. Like a senior engineer sharing real setups over coffee.
Length: 3-8 lines. Short and scannable.
Structure: Feature name → problem/context → what was done → benefit/result
Emojis: Sparingly and meaningfully (🔄 🛠️ ⚡ ⏩ 🌐 📡 🔒)
Hashtags: 2-4 max. Usually: #Tunneld #ElixirLang #PhoenixLiveView #SelfHosted #zrok #ZeroTrust
Mentions: Only when relevant (@zaborowska, @zrok, etc.)

## Main Template
[Feature Name] [emoji]

[One sentence: problem or context]

[What was built/changed]

• Bullet 1
• Bullet 2
• Bullet 3

[Benefit or how it feels now]

#Tunneld #zrok #ZeroTrust #SelfHosted

## Alternative: Quick Feature Drop
[Feature Name] [emoji]
[Problem in 1 sentence]

Added [technical thing]. Now:
• Benefit 1
• Benefit 2
• Benefit 3

[Result]

#Tunneld #PhoenixLiveView #SelfHosted
`;

// Helpers

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
}

function ensureOutputDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

async function prompt(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => { rl.close(); resolve(answer.trim()); });
  });
}

// Claude Code CLI Bridge

function askClaude(prompt) {
  try {
    const result = execFileSync("claude", ["-p", "--output-format", "text", prompt], {
      encoding: "utf-8",
      maxBuffer: 1024 * 1024,
      timeout: 120_000,
    });
    return result.trim();
  } catch (e) {
    console.error("Claude CLI error:", e.message);
    return null;
  }
}

function askClaudeJson(prompt) {
  // Ask claude and extract JSON from its response
  const raw = askClaude(prompt + "\n\nIMPORTANT: Respond with ONLY valid JSON, no markdown fences, no explanation.");
  if (!raw) return null;

  // Try to extract JSON from response (handle markdown fences if present)
  let cleaned = raw;
  const jsonMatch = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (jsonMatch) cleaned = jsonMatch[1].trim();

  // Try to find JSON array or object
  const start = cleaned.search(/[\[{]/);
  if (start === -1) return null;
  cleaned = cleaned.slice(start);

  try {
    return JSON.parse(cleaned);
  } catch {
    // Try to find the end of JSON
    let depth = 0;
    let inString = false;
    let escape = false;
    for (let i = 0; i < cleaned.length; i++) {
      const c = cleaned[i];
      if (escape) { escape = false; continue; }
      if (c === "\\") { escape = true; continue; }
      if (c === '"') { inString = !inString; continue; }
      if (inString) continue;
      if (c === "[" || c === "{") depth++;
      if (c === "]" || c === "}") {
        depth--;
        if (depth === 0) {
          try { return JSON.parse(cleaned.slice(0, i + 1)); } catch { break; }
        }
      }
    }
    console.error("Failed to parse JSON from Claude response");
    return null;
  }
}

// Browser Action Executor

class BrowserController {
  constructor(page, sessionDir) {
    this.page = page;
    this.sessionDir = sessionDir;
    this.screenshotCount = 0;
    this.screenshots = [];
  }

  async executeAction(action) {
    const { type, params } = action;

    switch (type) {
      case "goto":
        await this.page.goto(`${BASE_URL}${params.path}`, { waitUntil: "networkidle" });
        await this.page.waitForTimeout(500);
        return `Navigated to ${params.path}`;

      case "click":
        try {
          const el = await this.page.waitForSelector(params.selector, { timeout: 5000 });
          await el.click();
          await this.page.waitForTimeout(params.wait || 800);
          return `Clicked: ${params.selector}`;
        } catch (e) {
          return `FAILED to click "${params.selector}": ${e.message}`;
        }

      case "click_text":
        try {
          const el = await this.page.getByText(params.text, { exact: params.exact || false }).first();
          await el.click();
          await this.page.waitForTimeout(params.wait || 800);
          return `Clicked text: "${params.text}"`;
        } catch (e) {
          return `FAILED to click text "${params.text}": ${e.message}`;
        }

      case "fill":
        try {
          await this.page.fill(params.selector, params.value);
          return `Filled ${params.selector} with "${params.value}"`;
        } catch (e) {
          return `FAILED to fill "${params.selector}": ${e.message}`;
        }

      case "screenshot": {
        this.screenshotCount++;
        const name = params.name || `screenshot-${String(this.screenshotCount).padStart(2, "0")}`;
        const filename = `${name}.png`;
        const filepath = path.join(this.sessionDir, filename);

        const opts = { path: filepath, type: "png" };
        if (params.selector) {
          try {
            const el = await this.page.waitForSelector(params.selector, { timeout: 3000 });
            await el.screenshot(opts);
          } catch {
            await this.page.screenshot({ ...opts, fullPage: false });
          }
        } else if (params.full_page) {
          await this.page.screenshot({ ...opts, fullPage: true });
        } else {
          await this.page.screenshot({ ...opts, fullPage: false });
        }

        this.screenshots.push({ name, filename, filepath, description: params.description || "" });
        return `Screenshot saved: ${filename} — ${params.description || ""}`;
      }

      case "wait":
        await this.page.waitForTimeout(params.ms || 1000);
        return `Waited ${params.ms || 1000}ms`;

      case "scroll":
        await this.page.evaluate(
          ({ selector, direction }) => {
            const el = selector ? document.querySelector(selector) : window;
            const amount = direction === "up" ? -400 : 400;
            if (el === window) window.scrollBy(0, amount);
            else el.scrollTop += amount;
          },
          { selector: params.selector || null, direction: params.direction || "down" }
        );
        await this.page.waitForTimeout(300);
        return `Scrolled ${params.direction || "down"}`;

      case "resize":
        const width = params.width || 1440;
        const height = params.height || 900;
        await this.page.setViewportSize({ width, height });
        await this.page.waitForTimeout(500);
        return `Resized viewport to ${width}x${height}`;

      case "hover":
        try {
          await this.page.hover(params.selector);
          await this.page.waitForTimeout(300);
          return `Hovered: ${params.selector}`;
        } catch (e) {
          return `FAILED to hover "${params.selector}": ${e.message}`;
        }

      case "get_page_content":
        return `Page text:\n${await this.page.evaluate(() => document.body.innerText.slice(0, 3000))}`;

      case "get_visible_elements":
        const elements = await this.page.evaluate(() => {
          return Array.from(
            document.querySelectorAll("button, a, [phx-click], input, textarea, select, [role='button']")
          )
            .filter((el) => el.offsetParent !== null)
            .slice(0, 50)
            .map((el) => ({
              tag: el.tagName.toLowerCase(),
              text: el.innerText?.trim().slice(0, 60) || "",
              phxClick: el.getAttribute("phx-click") || "",
              phxValue: el.getAttribute("phx-value-type") || "",
              id: el.id || "",
              name: el.name || "",
            }));
        });
        return `Visible interactive elements:\n${JSON.stringify(elements, null, 2)}`;

      default:
        return `Unknown action type: ${type}`;
    }
  }
}

// Main Loop

async function run(featurePrompt) {
  const ts = timestamp();
  const sessionDir = path.join(OUTPUT_DIR, ts);
  ensureOutputDir(sessionDir);

  console.log(`\n📂 Output: ${sessionDir}\n`);
  console.log("🚀 Launching browser...");

  const browser = await chromium.launch({
    headless: false,
    args: ["--disable-blink-features=AutomationControlled"],
  });

  const page = await browser.newPage({ viewport: VIEWPORT });
  const controller = new BrowserController(page, sessionDir);

  try {
    // Step 1: Login
    console.log("🔐 Logging in...");
    await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
    await page.waitForTimeout(500);

    if (!page.url().includes("/dashboard")) {
      try {
        await page.fill('input[name="form[name]"]', LOGIN_USER);
        await page.fill('input[name="form[password]"]', LOGIN_PASS);
        await page.locator('button[type="submit"]').click();
        await page.waitForTimeout(1500);
        console.log("✅ Logged in\n");
      } catch {
        console.log("⚠️  Login form not found, continuing...\n");
      }
    }

    // Step 2: Agent Loop — Claude plans, Playwright executes
    const history = []; // track actions + results for context

    for (let turn = 0; turn < MAX_TURNS; turn++) {
      console.log(`\n🤖 Turn ${turn + 1}/${MAX_TURNS}`);

      // Get current page state
      const pageElements = await controller.executeAction({
        type: "get_visible_elements",
        params: {},
      });

      // Build prompt with full history
      const planPrompt = `${APP_CONTEXT}

## Task
Showcase this Tunneld feature for a tweet on X: "${featurePrompt}"

You are logged in and on the dashboard. Take 2-4 high-quality screenshots that showcase this feature well for social media.

## Available Actions (JSON format)
Each action is: { "type": "...", "params": { ... } }

Types:
- goto: { "path": "/dashboard" }
- click: { "selector": "css-selector", "wait": 800 }
- click_text: { "text": "Button Text", "exact": false, "wait": 800 }
- fill: { "selector": "input[name=...]", "value": "text" }
- screenshot: { "name": "descriptive-name", "description": "what this shows", "selector": null, "full_page": false }
- wait: { "ms": 1000 }
- scroll: { "direction": "down", "selector": null }
- hover: { "selector": "css-selector" }
- resize: { "width": 1440, "height": 900 } — resize the browser viewport. Common sizes: desktop 1440x900, tablet 768x1024, mobile 375x812

## Current Page State
URL: ${page.url()}
Viewport: ${page.viewportSize().width}x${page.viewportSize().height}
${pageElements}

## Actions Taken So Far
${history.length === 0 ? "None yet — this is the first turn." : history.map((h, i) => `Turn ${i + 1}: ${JSON.stringify(h.actions)} → Results: ${h.results.join("; ")}`).join("\n")}

## Instructions
Return a JSON array of actions to execute this turn. Example:
[
  { "type": "click_text", "params": { "text": "Internet Access" } },
  { "type": "screenshot", "params": { "name": "wifi-panel", "description": "WiFi sidebar showing connected network and options" } }
]

If you have taken enough screenshots (2-4) and are done, return: { "done": true }

Think about what would look best in a tweet. Show the feature in action, not just a static view.`;

      const actions = askClaudeJson(planPrompt);

      if (!actions) {
        console.log("   ⚠️ Could not parse Claude response, retrying...");
        continue;
      }

      // Check if done
      if (!Array.isArray(actions) && actions.done) {
        console.log("\n✅ Agent finished capturing screenshots.\n");
        break;
      }

      // Execute each action
      const actionList = Array.isArray(actions) ? actions : [actions];
      const results = [];

      for (const action of actionList) {
        console.log(`   ▶ ${action.type}: ${JSON.stringify(action.params).slice(0, 100)}`);
        const result = await controller.executeAction(action);
        results.push(result);
        console.log(`     ${result.slice(0, 150)}`);
      }

      history.push({ actions: actionList.map((a) => `${a.type}(${JSON.stringify(a.params)})`), results });
    }

    // Step 3: Generate Tweet
    if (controller.screenshots.length === 0) {
      console.log("⚠️  No screenshots taken. Check output above.");
      await browser.close();
      return;
    }

    console.log("✍️  Generating tweet...\n");

    const screenshotList = controller.screenshots
      .map((s, i) => `${i + 1}. ${s.filename} — ${s.description}`)
      .join("\n");

    const tweetPrompt = `${TWEET_STYLE}

Generate a tweet for X (Twitter) about this Tunneld feature:

Feature: "${featurePrompt}"

Screenshots that will be attached:
${screenshotList}

Write a tweet matching the style guide above. Return ONLY the raw tweet text — no markdown, no code blocks, no explanation. Just the tweet ready to copy-paste.`;

    const tweet = askClaude(tweetPrompt);

    if (tweet) {
      // Save tweet
      fs.writeFileSync(path.join(sessionDir, "tweet.txt"), tweet);

      // Save manifest
      fs.writeFileSync(
        path.join(sessionDir, "manifest.json"),
        JSON.stringify(
          {
            feature: featurePrompt,
            timestamp: new Date().toISOString(),
            screenshots: controller.screenshots.map((s) => ({
              filename: s.filename,
              description: s.description,
            })),
            tweet,
          },
          null,
          2
        )
      );

      // Print results
      console.log("━".repeat(60));
      console.log("📸 Screenshots:");
      for (const s of controller.screenshots) {
        console.log(`   ${s.filename} — ${s.description}`);
      }
      console.log("\n📝 Tweet:\n");
      console.log(tweet);
      console.log("\n" + "━".repeat(60));
      console.log(`\n📂 All files saved to: ${sessionDir}`);
      console.log(`   Open: open ${sessionDir}\n`);
    }
  } finally {
    await browser.close();
  }
}

// Entry Point

async function main() {
  let featurePrompt = process.argv.slice(2).join(" ");
  if (!featurePrompt) {
    featurePrompt = await prompt("🎯 What feature do you want to showcase?\n> ");
  }
  if (!featurePrompt) {
    console.log("No feature specified. Exiting.");
    process.exit(1);
  }

  // Verify claude CLI is available
  try {
    execFileSync("claude", ["--version"], { encoding: "utf-8", timeout: 5000 });
  } catch {
    console.error("❌ 'claude' CLI not found. Make sure Claude Code is installed and in your PATH.");
    process.exit(1);
  }

  await run(featurePrompt);
}

main().catch((e) => {
  console.error("Fatal error:", e);
  process.exit(1);
});
