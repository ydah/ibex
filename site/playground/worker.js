import { DefaultRubyVM } from "@ruby/4.0-wasm-wasi/dist/browser";
import rubyWasmUrl from "@ruby/4.0-wasm-wasi/dist/ruby+stdlib.wasm";

let vm;
let analyzer;

async function compileRubyModule() {
  const response = await fetch(rubyWasmUrl);
  if (!response.ok) throw new Error(`ruby.wasm request failed with HTTP ${response.status}`);
  try {
    return await WebAssembly.compileStreaming(response.clone());
  } catch {
    return WebAssembly.compile(await response.arrayBuffer());
  }
}

async function boot() {
  const [rubyModule, ibexSource] = await Promise.all([
    compileRubyModule(),
    fetch(new URL("./ibex.rb", import.meta.url)).then((response) => {
      if (!response.ok) throw new Error(`Ibex bundle request failed with HTTP ${response.status}`);
      return response.text();
    })
  ]);
  ({ vm } = await DefaultRubyVM(rubyModule, { consolePrint: false }));
  vm.eval(ibexSource);
  analyzer = vm.eval("IbexPlayground");
  self.postMessage({ type: "ready" });
}

function rubyString(value) {
  const bytes = new TextEncoder().encode(value);
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return vm.eval(`["${hex}"].pack("H*").force_encoding("UTF-8")`);
}

self.addEventListener("message", (event) => {
  const message = event.data;
  if (message.type !== "analyze" || !analyzer) return;

  try {
    const serialized = analyzer.call(
      "analyze",
      rubyString(message.source),
      rubyString(message.algorithm)
    );
    self.postMessage({ type: "result", id: message.id, result: JSON.parse(serialized.toString()) });
  } catch {
    self.postMessage({
      type: "result",
      id: message.id,
      result: {
        ok: false,
        diagnostics: [{
          message: "The browser analyzer could not process this grammar.",
          location: { file: "playground.y", line: 1, column: 1 }
        }]
      }
    });
  }
});

boot().catch(() => {
  self.postMessage({
    type: "boot-error",
    message: "ruby.wasm or the Ibex browser bundle could not be loaded."
  });
});
