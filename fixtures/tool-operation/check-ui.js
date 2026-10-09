// Optional JS-handler apparatus test with a minimal DOM boundary and real HTTP.
// This is NOT a browser, real input trajectory, or Agent workflow test.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const endpoint = process.argv[2];
const scenario = process.argv[3];
class Element {
  constructor() { this.listeners = {}; this.dataset = {}; this.value = ""; this.children = []; this.hidden = false; }
  addEventListener(name, handler) { this.listeners[name] = handler; }
  replaceChildren() { this.children = []; }
  append(child) { this.children.push(child); }
  focus() {}
  click() { return this.listeners.click(); }
}
const ids = ["identity", "new", "editor", "title", "body", "save", "cancel", "close", "status", "notes"];
const elements = Object.fromEntries(ids.map(id => [id, new Element()]));
elements.editor.hidden = true;
const document = {
  getElementById: id => elements[id], createElement: () => new Element(),
  addEventListener: () => {}
};
let loseUiEvent = false;
let loseSaveReply = false;
const fixtureFetch = async (path, options) => {
  if (path === "/__ui-event" && loseUiEvent) throw new Error("synthetic observer offline");
  const response = await fetch(endpoint + path, options);
  if (path === "/notes" && options && options.method === "POST" && loseSaveReply) {
    await response.text();
    throw new Error("synthetic client reply observer offline after real commit");
  }
  return response;
};
const context = vm.createContext({document, fetch: fixtureFetch,
  navigator: {platform: "MacIntel"}, location: {origin: endpoint}, console});
vm.runInContext(fs.readFileSync(__dirname + "/app.js", "utf8"), context);
async function wait(predicate) {
  const expires = Date.now() + 3000;
  while (!predicate() && Date.now() < expires) await new Promise(resolve => setTimeout(resolve, 10));
  assert.ok(predicate(), "bounded UI-handler wait failed");
}
(async () => {
  await wait(() => elements.status.dataset.state === "clean");
  elements.new.click();
  elements.title.value = "  Sprint note  ";
  elements.body.value = "draft-A";
  if (scenario === "pending") {
    loseUiEvent = true;
    elements.save.click();
    await new Promise(resolve => setTimeout(resolve, 50));
    elements.save.click();
    await wait(() => elements.status.dataset.state === "saved");
  } else {
    loseSaveReply = true;
    elements.save.click();
    await wait(() => elements.status.dataset.state === "unknown");
    elements.save.click();
    await new Promise(resolve => setTimeout(resolve, 400));
  }
  const notes = await (await fetch(endpoint + "/notes")).json();
  assert.equal(notes.length, 1, "a pending or unknown write must not create a second note");
  assert.equal(notes[0].title, "Sprint note");
  assert.equal(notes[0].body, "draft-A");
  console.log(`JS handler apparatus ${scenario}: one persisted note`);
})().catch(error => { console.error(error); process.exitCode = 1; });
