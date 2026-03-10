(function () {
  const form = document.getElementById("termsForm");
  if (!form) return;

  const acceptBtn = document.getElementById("acceptBtn");

  function isScrollAtBottom(el) {
    return el.scrollTop + el.clientHeight >= el.scrollHeight - 2;
  }

  function updateAcceptButton() {
    const requiredTerms = form.querySelectorAll('.term-card[data-required="true"]');
    const allRequiredChecked = Array.from(requiredTerms).every((term) => {
      const cb = term.querySelector(".tc-checkbox");
      return cb && cb.checked;
    });

    if (acceptBtn) {
      acceptBtn.disabled = !allRequiredChecked;
    }
  }

  function setPill(termEl, name, text, warn) {
    const pill = termEl.querySelector('[data-pill="' + name + '"]');
    if (!pill) return;
    pill.textContent = text;
    pill.className = warn ? "pill pill-warn" : "pill";
  }

  function setHintOk(termEl) {
    const hint = termEl.querySelector("[data-hint]");
    if (!hint) return;
    hint.classList.add("ok");
    hint.textContent = "Done. You can now accept.";
  }

  function escapeHtml(str) {
    return String(str)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  async function loadExternal(termEl) {
    const url = termEl.getAttribute("data-url") || "";
    if (!url) return;

    const box = termEl.querySelector('[data-scrollbox="true"]');
    const content = termEl.querySelector("[data-content]");
    if (!box || !content) return;

    try {
      const resp = await fetch(url, {
        method: "GET",
        credentials: "omit",
        cache: "no-store"
      });

      if (!resp.ok) {
        throw new Error("HTTP " + resp.status);
      }

      const text = await resp.text();

      content.innerHTML =
        "<pre>" + escapeHtml(text) + "</pre>";

      box.setAttribute("aria-busy", "false");
      setPill(termEl, "load", "Loaded", false);

      const isRequired = termEl.getAttribute("data-required") === "true";
      const cb = termEl.querySelector(".tc-checkbox");

      if (!cb || cb.checked || !isRequired) return;

      if (box.scrollHeight <= box.clientHeight + 2) {
        cb.disabled = false;
        setHintOk(termEl);
        setPill(termEl, "gate", "Ready", false);
      }
    } catch (e) {
      box.setAttribute("aria-busy", "false");
      content.textContent = "Failed to load terms content. Please open 'View details'.";
      setPill(termEl, "load", "Load failed", true);
    }
  }

  function bindGate(termEl) {
    const isRequired = termEl.getAttribute("data-required") === "true";
    if (!isRequired) return;

    const cb = termEl.querySelector(".tc-checkbox");
    const box = termEl.querySelector('[data-scrollbox="true"]');
    if (!cb || !box) return;

    if (cb.checked) {
      cb.disabled = false;
      setHintOk(termEl);
      setPill(termEl, "gate", "Ready", false);
      return;
    }

    const onScroll = () => {
      if (cb.disabled && isScrollAtBottom(box)) {
        cb.disabled = false;
        setHintOk(termEl);
        setPill(termEl, "gate", "Ready", false);
      }
    };

    box.addEventListener("scroll", onScroll);
    box.addEventListener("keyup", onScroll);
  }

  const terms = form.querySelectorAll(".term-card[data-term-key]");
  terms.forEach((termEl) => {
    loadExternal(termEl);
    bindGate(termEl);
  });

  form.addEventListener("change", (e) => {
    const t = e.target;
    if (!t || t.type !== "checkbox") return;
    updateAcceptButton();
  });

  updateAcceptButton();
})();