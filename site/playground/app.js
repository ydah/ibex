const SAMPLES = {
  calculator: `class Calculator
token NUMBER
left '+'
left '*'
rule
  expression : expression '+' expression
             | expression '*' expression
             | NUMBER
end
`,
  json: `class JsonParser
token LBRACE RBRACE LBRACKET RBRACKET STRING NUMBER
rule
  value : STRING | NUMBER | object | array
  object : LBRACE RBRACE | LBRACE members RBRACE
  members : STRING ':' value | members ',' STRING ':' value
  array : LBRACKET RBRACKET | LBRACKET values RBRACKET
  values : value | values ',' value
end
`,
  conflict: `class AmbiguousParser
token NUMBER
rule
  expression : expression '+' expression
             | expression '*' expression
             | NUMBER
end
`,
  expression: `class Browser::ExpressionParser
token NUMBER
left '+' '-'
left '*' '/'
rule
  expression : expression '+' expression
             | expression '-' expression
             | expression '*' expression
             | expression '/' expression
             | NUMBER
end
`
};

const ANALYSIS_TIMEOUT_MS = 15_000;
const elements = {
  form: document.querySelector("#playground-form"),
  source: document.querySelector("#grammar-source"),
  sourceSize: document.querySelector("#source-size"),
  sample: document.querySelector("#sample"),
  algorithm: document.querySelector("#algorithm"),
  analyze: document.querySelector("#analyze-button"),
  reset: document.querySelector("#reset-button"),
  status: document.querySelector("#status"),
  summary: document.querySelector("#summary"),
  diagnostics: document.querySelector("#diagnostics"),
  conflicts: document.querySelector("#conflicts"),
  resultActions: document.querySelector("#result-actions"),
  download: document.querySelector("#download-button"),
  copy: document.querySelector("#copy-button")
};
elements.tabs = [...document.querySelectorAll("[data-tab]")];
elements.panels = Object.fromEntries(
  ["summary", "diagnostics", "conflicts", "automaton"].map((name) => [name, document.querySelector(`#panel-${name}`)])
);
elements.automaton = document.querySelector("#automaton-output code");
elements.summaryEmpty = document.querySelector("#summary-empty");

let worker;
let requestSequence = 0;
let pendingRequest = null;
let latestResult = null;

function createWorker() {
  worker?.terminate();
  worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
  worker.addEventListener("message", handleWorkerMessage);
  worker.addEventListener("error", () => failAnalysis("The analyzer worker stopped unexpectedly."));
  setStatus("Loading the analyzer…", "loading");
  elements.analyze.disabled = true;
}

function handleWorkerMessage(event) {
  const message = event.data;
  if (message.type === "ready") {
    setStatus("Ready. Your grammar stays in this browser.", "success");
    elements.analyze.disabled = false;
    return;
  }
  if (message.type === "boot-error") {
    setStatus("The browser analyzer could not start.", "error");
    renderDiagnostics([{ message: message.message, location: null }]);
    return;
  }
  if (message.type !== "result" || message.id !== pendingRequest?.id) return;

  clearTimeout(pendingRequest.timeout);
  pendingRequest = null;
  elements.analyze.disabled = false;
  latestResult = message.result;
  renderResult(message.result);
}

function submitAnalysis(event) {
  event.preventDefault();
  if (pendingRequest) return;

  const id = ++requestSequence;
  elements.analyze.disabled = true;
  setStatus("Building the automaton…", "loading");
  pendingRequest = {
    id,
    timeout: setTimeout(() => {
      pendingRequest = null;
      failAnalysis("Analysis exceeded 15 seconds and was stopped.");
      createWorker();
    }, ANALYSIS_TIMEOUT_MS)
  };
  worker.postMessage({
    type: "analyze",
    id,
    source: elements.source.value,
    algorithm: elements.algorithm.value
  });
}

function failAnalysis(message) {
  if (pendingRequest) {
    clearTimeout(pendingRequest.timeout);
    pendingRequest = null;
  }
  latestResult = null;
  elements.analyze.disabled = false;
  setStatus(message, "error");
  renderDiagnostics([{ message, location: null }]);
  renderConflicts([]);
  elements.summary.classList.add("hidden");
  elements.summaryEmpty.classList.remove("hidden");
  elements.automaton.textContent = "{}";
  elements.resultActions.classList.add("hidden");
  selectTab("diagnostics");
}

function renderResult(result) {
  renderDiagnostics(result.diagnostics || []);
  if (!result.ok) {
    latestResult = null;
    setStatus("Fix the diagnostics and try again.", "error");
    renderConflicts([]);
    elements.summary.classList.add("hidden");
    elements.summaryEmpty.classList.remove("hidden");
    elements.automaton.textContent = "{}";
    selectTab("diagnostics");
    elements.resultActions.classList.add("hidden");
    return;
  }

  renderSummary(result.summary);
  renderConflicts(result.conflicts, result.conflicts_truncated);
  elements.automaton.textContent = JSON.stringify(result.automaton, null, 2);
  elements.resultActions.classList.remove("hidden");
  selectTab("summary");
  const conflictCount = result.summary.conflicts;
  setStatus(
    conflictCount === 0
      ? `${result.algorithm.toUpperCase()} automaton built without conflicts.`
      : `${result.algorithm.toUpperCase()} automaton built with ${conflictCount} conflict${conflictCount === 1 ? "" : "s"}.`,
    conflictCount === 0 ? "success" : "error"
  );
}

function renderSummary(summary) {
  const labels = {
    terminals: "Terminals",
    nonterminals: "Nonterminals",
    productions: "Productions",
    states: "States",
    conflicts: "Conflicts"
  };
  elements.summary.replaceChildren(
    ...Object.entries(labels).map(([key, label]) => {
      const wrapper = document.createElement("div");
      const term = document.createElement("dt");
      const value = document.createElement("dd");
      term.textContent = label;
      value.textContent = String(summary[key]);
      wrapper.append(term, value);
      return wrapper;
    })
  );
  elements.summary.classList.remove("hidden");
  elements.summaryEmpty.classList.add("hidden");
}

function renderDiagnostics(diagnostics) {
  if (diagnostics.length === 0) {
    elements.diagnostics.replaceChildren(emptyItem("No diagnostics."));
    return;
  }
  elements.diagnostics.replaceChildren(
    ...diagnostics.map((diagnostic) => {
      const item = document.createElement("li");
      item.className = "diagnostic";
      const location = diagnostic.location;
      if (location) {
        const prefix = document.createElement("span");
        prefix.className = "diagnostic-location";
        prefix.textContent = `${location.file}:${location.line}:${location.column} `;
        item.append(prefix);
      }
      item.append(document.createTextNode(diagnostic.message));
      return item;
    })
  );
}

function renderConflicts(conflicts, truncated = false) {
  if (conflicts.length === 0) {
    elements.conflicts.replaceChildren(emptyItem("No conflicts."));
    return;
  }
  const items = conflicts.map((entry) => {
    const item = document.createElement("li");
    const heading = document.createElement("div");
    const code = document.createElement("code");
    code.textContent = `state ${entry.state} · ${entry.token || "unknown token"}`;
    heading.append(code, document.createTextNode(` · ${entry.conflict.type.replaceAll("_", "/")}`));
    item.append(heading);

    const example = entry.counterexample;
    if (example?.sentence?.length) {
      const detail = document.createElement("div");
      detail.textContent = `${example.unifying ? "Unifying" : "Reachability"} example: ${example.sentence.join(" ")}`;
      item.append(detail);
    }
    return item;
  });
  if (truncated) items.push(emptyItem("Additional conflicts were omitted from this view."));
  elements.conflicts.replaceChildren(...items);
}

function emptyItem(message) {
  const item = document.createElement("li");
  item.className = "empty";
  item.textContent = message;
  return item;
}

function setStatus(message, kind) {
  elements.status.textContent = message;
  elements.status.dataset.kind = kind;
}

function updateSourceSize() {
  const bytes = new TextEncoder().encode(elements.source.value).length;
  elements.sourceSize.textContent = `${bytes.toLocaleString()} / 100,000 bytes`;
}

function resetSample() {
  elements.source.value = SAMPLES[elements.sample.value] || SAMPLES.calculator;
  updateSourceSize();
  elements.source.focus();
}

function selectSample(sample) {
  if (!SAMPLES[sample]) return;
  elements.sample.value = sample;
  resetSample();
}

function selectTab(name) {
  elements.tabs.forEach((tab) => {
    const selected = tab.dataset.tab === name;
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
  });
  Object.entries(elements.panels).forEach(([panelName, panel]) => {
    panel.classList.toggle("hidden", panelName !== name);
  });
}

function selectSampleFromLocation() {
  const querySample = new URLSearchParams(window.location.search).get("sample");
  const fragmentSample = new URLSearchParams(window.location.hash.slice(1)).get("sample");
  selectSample(querySample || fragmentSample || "calculator");
}

function downloadAutomaton() {
  if (!latestResult?.automaton) return;
  const blob = new Blob([`${JSON.stringify(latestResult.automaton, null, 2)}\n`], {
    type: "application/json"
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "automaton.json";
  link.click();
  URL.revokeObjectURL(url);
}

async function copySummary() {
  if (!latestResult?.summary) return;
  const summary = Object.entries(latestResult.summary)
    .map(([name, value]) => `${name}: ${value}`)
    .join("\n");
  try {
    await navigator.clipboard.writeText(`${latestResult.algorithm}\n${summary}`);
    setStatus("Summary copied to the clipboard.", "success");
  } catch {
    setStatus("Clipboard access is unavailable in this browser.", "error");
  }
}

elements.form.addEventListener("submit", submitAnalysis);
elements.reset.addEventListener("click", resetSample);
elements.sample.addEventListener("change", () => selectSample(elements.sample.value));
elements.source.addEventListener("input", updateSourceSize);
elements.source.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
    event.preventDefault();
    elements.form.requestSubmit();
  }
});
elements.download.addEventListener("click", downloadAutomaton);
elements.copy.addEventListener("click", copySummary);
elements.tabs.forEach((tab, index) => {
  tab.addEventListener("click", () => selectTab(tab.dataset.tab));
  tab.addEventListener("keydown", (event) => {
    if (!["ArrowRight", "ArrowLeft", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const next = event.key === "Home" ? 0 : event.key === "End" ? elements.tabs.length - 1 :
      (index + (event.key === "ArrowRight" ? 1 : -1) + elements.tabs.length) % elements.tabs.length;
    elements.tabs[next].focus();
    selectTab(elements.tabs[next].dataset.tab);
  });
});

selectSampleFromLocation();
selectTab("summary");
createWorker();
