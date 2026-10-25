// The page asks the API through nginx: /api/... goes to the same address the
// page came from, so the browser needs no second host or port.
"use strict";

const errorBox = document.getElementById("error");

// api sends one request to /api/<path> and returns the JSON answer. A status
// other than 2xx becomes an error with the API's message, or with the status
// line when the answer isn't JSON (nginx's own 502 page, for example).
async function api(path, options) {
  const res = await fetch("/api/" + path, options);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(body.error || `${res.status} ${res.statusText}`);
  }
  return body;
}

// show fills the list with one line per item. textContent, not innerHTML, so
// a name like <script> is shown as text and never runs.
function show(listId, items, line) {
  const lines = items.map((item) => {
    const li = document.createElement("li");
    li.textContent = line(item);
    return li;
  });
  document.getElementById(listId).replaceChildren(...lines);
}

async function refresh() {
  try {
    const [patients, appointments] = await Promise.all([api("patients"), api("appointments")]);
    const names = new Map(patients.map((p) => [p.id, p.name]));

    show("patients", patients, (p) => `${p.name}, ${p.phone || p.email}`);
    show("appointments", appointments, (a) =>
      `${names.get(a.patient_id)}, ${new Date(a.starts_at).toLocaleString()}: ` +
      (a.reminded_at ? `reminder sent ${new Date(a.reminded_at).toLocaleTimeString()}` : "no reminder yet"));

    const select = document.getElementById("patient-select");
    const chosen = select.value;
    select.replaceChildren(...patients.map((p) => new Option(p.name, p.id)));
    select.value = chosen || select.value;

    errorBox.textContent = "";
  } catch (err) {
    errorBox.textContent = err.message;
  }
}

// send POSTs body as JSON, then empties the form and reloads the lists.
async function send(path, body, form) {
  try {
    await api(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    form.reset();
    await refresh();
  } catch (err) {
    errorBox.textContent = err.message;
  }
}

document.getElementById("patient-form").addEventListener("submit", (event) => {
  event.preventDefault();
  send("patients", Object.fromEntries(new FormData(event.target)), event.target);
});

document.getElementById("appointment-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const data = new FormData(event.target);
  send("appointments", {
    patient_id: Number(data.get("patient_id")),
    // The picker gives local time without a zone. new Date reads it as local
    // time, and toISOString sends it in UTC, which is how the API stores it.
    starts_at: new Date(data.get("starts_at")).toISOString(),
  }, event.target);
});

refresh();
setInterval(refresh, 10000); // every 10 seconds, so a reminder shows up without a reload
