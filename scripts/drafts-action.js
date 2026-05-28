// Selene Silent Send — Drafts Action
//
// SETUP: In Drafts, create an action with this script as a "Script" step.
//        Set it as an "After Success" action to auto-run on save.
//        Only shows UI on failure.
//
// INSTALL: Drafts → Actions → + → Script → paste this file
//
// TARGET: http://Chases-Mac-mini.local:5678/webhook/api/drafts
//         Works from iPhone, iPad, and Mac on the same network.
//         Change the hostname if your Mac mini's name changes.

const PROCESS_URL = "http://Chases-Mac-mini.local:5678/webhook/api/drafts";

const payload = {
    title: draft.displayTitle || "Untitled",
    content: draft.content,
    created_at: new Date().toISOString(),
    capture_type: "drafts",
    source_uuid: draft.uuid,
};

try {
    const http = HTTP.create();
    const resp = http.request({
        url: PROCESS_URL,
        method: "POST",
        headers: { "Content-Type": "application/json" },
        data: payload,
        timeout: 15,
    });

    if (resp.success) {
        draft.addTag("selene-sent");
        draft.update();
    } else {
        app.displayErrorMessage(`Selene: ${resp.statusCode || "no response"}`);
    }
} catch (e) {
    app.displayErrorMessage(`Selene: ${e.message || e}`);
}
