import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import test from "node:test";
import { DefaultRubyVM } from "@ruby/4.0-wasm-wasi/dist/node";

const output = new URL("../../tmp/site/", import.meta.url);

function rubyString(vm, value) {
  const bytes = new TextEncoder().encode(value);
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return vm.eval(`["${hex}"].pack("H*").force_encoding("UTF-8")`);
}

test("site is self-hosted and applies a restrictive policy", async () => {
  const pages = await Promise.all([
    readFile(new URL("index.html", output), "utf8"),
    readFile(new URL("getting-started/index.html", output), "utf8"),
    readFile(new URL("docs/index.html", output), "utf8"),
    readFile(new URL("project/index.html", output), "utf8"),
    readFile(new URL("playground/index.html", output), "utf8"),
    readFile(new URL("compatibility/index.html", output), "utf8"),
    readFile(new URL("extensions/index.html", output), "utf8"),
    readFile(new URL("experimental/index.html", output), "utf8"),
    readFile(new URL("gallery/index.html", output), "utf8")
  ]);

  for (const html of pages) {
    assert.match(html, /Content-Security-Policy/);
    assert.match(html, /wasm-unsafe-eval/);
    assert.match(html, /Skip to content/);
    assert.match(html, /rel="canonical"/);
    assert.match(html, /property="og:title"/);
    assert.doesNotMatch(html, /<script\b[^>]+src=["']https?:\/\//);
    assert.doesNotMatch(html, /<link\b[^>]+rel=["']stylesheet["'][^>]+href=["']https?:\/\//);
  }
});

test("Pages renders task documentation from canonical Markdown", async () => {
  const [source, gettingStarted, grammar, status, sitemap] = await Promise.all([
    readFile(new URL("../../docs/getting-started.md", import.meta.url), "utf8"),
    readFile(new URL("docs/getting-started/index.html", output), "utf8"),
    readFile(new URL("docs/grammar-reference/index.html", output), "utf8"),
    readFile(new URL("docs/status/index.html", output), "utf8"),
    readFile(new URL("sitemap.xml", output), "utf8")
  ]);

  assert.match(source, /title: Getting started/);
  assert.match(gettingStarted, /Install the generator/);
  assert.match(grammar, /Grammar reference/);
  assert.match(status, /independent review/);
  assert.match(sitemap, /docs\/grammar-reference\//);
  assert.match(sitemap, /getting-started\//);
});

test("documentation separates maturity levels and publishes the covered gallery", async () => {
  const home = await readFile(new URL("index.html", output), "utf8");
  const compatibility = await readFile(new URL("compatibility/index.html", output), "utf8");
  const extensions = await readFile(new URL("extensions/index.html", output), "utf8");
  const experimental = await readFile(new URL("experimental/index.html", output), "utf8");
  const gallery = await readFile(new URL("gallery/index.html", output), "utf8");

  assert.match(home, /DOCUMENTATION BY MATURITY/);
  assert.match(compatibility, /PERMANENT DEFAULT CONTRACT/);
  assert.match(compatibility, /release-readiness\//);
  assert.match(compatibility, /stability\//);
  assert.match(extensions, /EXPLICIT OPT-IN SURFACE/);
  assert.match(extensions, /stability\//);
  assert.match(experimental, /EVIDENCE BEFORE PROMOTION/);
  assert.match(experimental, /stability\//);
  assert.match(experimental, /Syntax-only incremental CST sessions are shipped as Experimental/);
  assert.match(experimental, /Generalized LR and GLR ambiguity handling are not shipped/);
  assert.doesNotMatch(experimental, /incremental parsing\s+are not shipped/);
  assert.match(gallery, /100% production coverage in CI/);
  for (const grammar of ["calculator.y", "csv.y", "ini.y", "json.y", "tiny_language.y"]) {
    assert.match(gallery, new RegExp(grammar.replace(".", "\\.")));
  }
});

test("playground ships its Ruby and WebAssembly assets", async () => {
  const ruby = await stat(new URL("playground/ibex.rb", output));
  assert.ok(ruby.size > 100_000);

  const worker = await readFile(new URL("playground/worker.js", output), "utf8");
  const wasmMatch = worker.match(/\.\/assets\/ruby\+stdlib-[A-Z0-9]+\.wasm/);
  assert.ok(wasmMatch, "worker should reference the emitted ruby.wasm asset");

  const wasm = await stat(new URL(`playground/${wasmMatch[0].slice(2)}`, output));
  assert.ok(wasm.size > 1_000_000);
});

test("playground exposes accessible controls and worker limits", async () => {
  const html = await readFile(new URL("playground/index.html", output), "utf8");
  const app = await readFile(new URL("playground/app.js", output), "utf8");

  assert.match(html, /aria-live="polite"/);
  assert.match(html, /for="grammar-source"/);
  assert.match(html, /id="sample"/);
  assert.match(html, /data-tab="automaton"/);
  assert.match(html, /aria-controls="panel-conflicts"/);
  assert.match(html, /type="submit"/);
  assert.match(app, /15e3|15000|15_000/);
  assert.match(app, /new Worker/);
  assert.match(app, /SAMPLES/);
  assert.match(app, /URLSearchParams/);
});

test("ruby.wasm loads the browser bundle and analyzes a grammar", { timeout: 30_000 }, async () => {
  const wasmUrl = import.meta.resolve("@ruby/4.0-wasm-wasi/dist/ruby+stdlib.wasm");
  const rubyModule = await WebAssembly.compile(await readFile(new URL(wasmUrl)));
  const { vm } = await DefaultRubyVM(rubyModule);
  vm.eval(await readFile(new URL("playground/ibex.rb", output), "utf8"));
  const analyzer = vm.eval("IbexPlayground");
  const source = [
    "class SmokeParser",
    "token NUMBER",
    "rule",
    '  value : NUMBER { result = "#{raise "must not execute"}" }',
    "end",
    ""
  ].join("\n");
  const result = analyzer.call(
    "analyze",
    rubyString(vm, source),
    rubyString(vm, "lalr")
  );
  const document = JSON.parse(result.toString());

  assert.equal(document.ok, true);
  assert.equal(document.algorithm, "lalr1");
  assert.ok(document.summary.states > 0);
});
