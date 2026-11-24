"""HTML page of the frontend (rendered with Jinja autoescaping).

Inline CSS/JS are allowed by a per-response CSP nonce; nothing is loaded from
other origins.
"""

PAGE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Hello Commit</title>
  <link rel="icon" href="data:,">
  <style nonce="{{ nonce }}">
    :root { --bg: #eef2f7; --card: #ffffff; --ink: #14213d; --muted: #5b6780;
            --line: #dbe2ec; --accent: #0b6e69; --accent-ink: #ffffff; --error: #b3261e; }
    @media (prefers-color-scheme: dark) {
      :root { --bg: #0e1522; --card: #172032; --ink: #eaf0fa; --muted: #9fadc6;
              --line: #2a364d; --accent: #4fd1c5; --accent-ink: #06201e; --error: #ff9a92; }
    }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px 16px;
           background: var(--bg); color: var(--ink);
           font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
    main { width: 100%; max-width: 520px; padding: 40px 32px; text-align: center;
           background: var(--card); border: 1px solid var(--line); border-radius: 16px; }
    h1 { margin: 0; font-size: clamp(1.75rem, 7vw, 2.75rem); letter-spacing: -0.02em; overflow-wrap: anywhere; }
    #value { color: var(--accent); font-variant-numeric: tabular-nums; }
    p { margin: 12px 0 0; color: var(--muted); line-height: 1.5; }
    button { margin-top: 28px; min-height: 48px; padding: 0 32px; font: inherit; font-weight: 600;
             color: var(--accent-ink); background: var(--accent); border: 0; border-radius: 10px; cursor: pointer; }
    button:hover { filter: brightness(1.08); }
    button:focus-visible, a:focus-visible { outline: 3px solid var(--accent); outline-offset: 3px; }
    button:disabled { opacity: .6; cursor: progress; }
    #status { min-height: 1.5em; }
    #status.error { color: var(--error); }
    .footer { margin-top: 20px; font-size: .8125rem; }
    .trace { margin-top: 24px; padding-top: 20px; border-top: 1px solid var(--line); font-size: .875rem; color: var(--muted); }
    .trace a { display: inline-block; margin-top: 4px; color: var(--accent); overflow-wrap: anywhere;
               font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  </style>
</head>
<body>
  <main>
    <h1>Hello Commit <span id="value">{{ value if value is not none else "" }}</span></h1>
    <p>The counter is stored in PostgreSQL and changes only when you click.</p>
    <button id="increment" type="button">Update counter</button>
    <p id="status" role="status"{% if error %} class="error"{% endif %}>{{ error or "" }}</p>
    <div class="trace">
      <span id="trace-label">X-Ray trace of this page load</span><br>
      <a id="trace" href="{{ trace_base }}{{ trace_id }}" target="_blank" rel="noopener noreferrer">{{ trace_id }}</a>
    </div>
    <p class="footer">Built and deployed by GitHub Actions and CodeDeploy</p>
    <noscript><p>JavaScript is needed to update the counter.</p></noscript>
  </main>
  <script nonce="{{ nonce }}">
    (function () {
      var traceBase = {{ trace_base|tojson }};
      var button = document.getElementById("increment");
      var status = document.getElementById("status");
      var trace = document.getElementById("trace");

      function show(text, isError) {
        status.textContent = text;
        status.className = isError ? "error" : "";
      }

      button.addEventListener("click", async function () {
        button.disabled = true;
        show("Updating\\u2026", false);
        try {
          var resp = await fetch("/api/increment", { method: "POST", cache: "no-store" });
          var data = await resp.json().catch(function () { return {}; });
          if (data.trace_id) {
            trace.textContent = data.trace_id;
            trace.href = traceBase + data.trace_id;
            document.getElementById("trace-label").textContent = "X-Ray trace of your last click";
          }
          if (!resp.ok) { throw new Error(data.error || "HTTP " + resp.status); }
          document.getElementById("value").textContent = data.value;
          show("Counter updated", false);
        } catch (err) {
          show("The counter was not confirmed (" + err.message + "). Reload the page to see its value.", true);
        } finally {
          button.disabled = false;
        }
      });
    })();
  </script>
</body>
</html>
"""
