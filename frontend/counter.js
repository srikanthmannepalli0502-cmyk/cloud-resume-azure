// Calls the visitor-counter API and shows the new count in the footer.
(async function () {
  const el = document.getElementById("visitor-count");
  const apiUrl = window.RESUME_CONFIG && window.RESUME_CONFIG.apiUrl;
  if (!el || !apiUrl) return;

  try {
    // POST with no body is a CORS "simple request", so the browser skips the preflight.
    const res = await fetch(apiUrl, { method: "POST" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    el.textContent = Number(data.count).toLocaleString();
  } catch (err) {
    console.error("Visitor counter failed:", err);
    el.textContent = "unavailable";
  }
})();
