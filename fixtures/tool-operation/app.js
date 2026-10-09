"use strict";
const elements = Object.fromEntries(["identity", "new", "editor", "title", "body", "save", "cancel", "close", "status", "notes"]
  .map(id => [id, document.getElementById(id)]));
let state = "loading";
let config;
let savedId = null;
let submitting = false;
const setState = (next, text) => {
  state = next;
  elements.status.dataset.state = next;
  elements.status.textContent = text;
};
async function request(path, options) {
  const response = await fetch(path, options);
  const body = await response.json();
  if (!response.ok) throw Object.assign(new Error("Request rejected"), {body, status: response.status});
  return body;
}
function event(action) {
  // Browser input trajectory; business proof remains reopen + independent store observer.
  return request("/__ui-event", {method: "POST", headers: {"Content-Type": "application/json"},
    body: JSON.stringify({action, state})});
}
async function list() {
  const notes = await request("/notes");
  elements.notes.replaceChildren();
  for (const note of notes) {
    const li = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = note.title;
    button.dataset.noteId = note.id;
    button.addEventListener("click", async () => {
      try {
        await event("open");
        const persisted = await request("/notes/" + note.id);
        savedId = persisted.id;
        elements.title.value = persisted.title;
        elements.body.value = persisted.body;
        elements.editor.hidden = false;
        setState("saved", "Reopened");
      } catch { setState("error", "Could not reopen"); }
    });
    li.append(button);
    elements.notes.append(li);
  }
}
async function save(action) {
  void event(action).catch(() => { elements.status.dataset.inputObserver = "unavailable"; });
  if (submitting || state === "unknown" || state === "loading" || elements.editor.hidden) return;
  if (!elements.title.value.trim()) {
    setState("rejected", "Title required");
    return;
  }
  if (savedId !== null) {
    setState("saved", "Already saved; create a new note to submit a draft");
    return;
  }
  const payload = {title: elements.title.value, body: elements.body.value};
  submitting = true;
  setState("submitting", "Saving");
  try {
    const receipt = await request("/notes", {method: "POST", headers: {"Content-Type": "application/json"},
      body: JSON.stringify(payload)});
    savedId = receipt.id;
    setState("saved", "Saved");
    await list();
  } catch (error) {
    // No automatic resend: an unknown write may already have committed.
    setState("unknown", "Save outcome unknown; reconcile before another submission");
  } finally {
    submitting = false;
  }
}
elements.new.addEventListener("click", () => {
  if (state === "submitting" || state === "unknown") return;
  savedId = null;
  elements.title.value = "";
  elements.body.value = "";
  elements.editor.hidden = false;
  setState("draft", "Draft");
  elements.title.focus();
});
elements.save.addEventListener("click", () => { void save("button"); });
elements.cancel.addEventListener("click", async () => {
  if (state === "submitting" || state === "unknown") return;
  await event("cancel");
  elements.editor.hidden = true;
  elements.title.value = "";
  elements.body.value = "";
  savedId = null;
  setState("cancelled", "Cancelled");
  await list();
});
elements.close.addEventListener("click", async () => {
  if (state === "submitting" || state === "unknown") return;
  await event("close");
  elements.editor.hidden = true;
  setState("clean", "Editor closed");
  await list();
});
document.addEventListener("keydown", eventObject => {
  const mac = /Mac/i.test(navigator.platform);
  const modifier = mac ? eventObject.metaKey && !eventObject.ctrlKey : eventObject.ctrlKey && !eventObject.metaKey;
  if (eventObject.key === "Enter" && modifier && !eventObject.altKey && !eventObject.shiftKey) {
    eventObject.preventDefault();
    if (config && !config.shortcut_disabled) void save("shortcut");
  }
});
(async () => {
  try {
    const identity = await request("/identity");
    config = await request("/ui-config");
    elements.identity.textContent = `run=${identity.run_id} instance=${identity.instance_id} pid=${identity.pid} origin=${location.origin}`;
    elements.identity.dataset.instanceId = identity.instance_id;
    await list();
    setState("clean", "Ready");
  } catch { setState("error", "Could not bind instance"); }
})();
