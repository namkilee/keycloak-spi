(function(){
  const form = document.getElementById("termsForm");
  if (!form) return;

  const acceptBtn = document.getElementById("acceptBtn");

  function isScrollAtBottom(el){
    return el.scrollTop + el.clientHeight >= el.scrollHeight - 2;
  }

  function updateAcceptButton(){
    const requiredTerms = form.querySelectorAll('.term-card[data-required="true"]');
    const allRequiredChecked = Array.from(requiredTerms).every(term => {
      const cb = term.querySelector(".tc-checkbox");
      return cb && cb.checked;
    });
    if (acceptBtn) acceptBtn.disabled = !allRequiredChecked;
  }

  function setPill(termEl, name, text, warn){
    const pill = termEl.querySelector('[data-pill="'+name+'"]');
    if (!pill) return;
    pill.textContent = text;
    pill.className = warn ? "pill pill-warn" : "pill";
  }

  function setHintOk(termEl){
    const hint = termEl.querySelector("[data-hint]");
    if (!hint) return;
    hint.classList.add("ok");
    hint.textContent = "Done. You can now accept.";
  }

  function escapeHtml(str){
    return String(str)
      .replaceAll("&","&amp;")
      .replaceAll("<","&lt;")
      .replaceAll(">","&gt;")
      .replaceAll('"',"&quot;")
      .replaceAll("'","&#039;");
  }

  async function loadExternal(termEl){
    const url = termEl.getAttribute("data-url") || "";
    if (!url) return;

    const box = termEl.querySelector('[data-scrollbox="true"]');
    const content = termEl.querySelector("[data-content]");
    if (!box || !content) return;

    try{
      const resp = await fetch(url, { method: "GET", credentials: "omit", cache: "no-store" });
      if (!resp.ok) throw new Error("HTTP " + resp.status);

      const ct = (resp.headers.get("content-type") || "").toLowerCase();
      const text = await resp.text();

      // 보수적 기본값: HTML이면 위험할 수 있어 text로 처리.
      // (정말 신뢰된 소스이고 HTML 렌더링 필요하면 아래 분기에서 innerHTML 허용하도록 바꾸면 됨)
      if (ct.includes("text/html")) {
        content.innerHTML =
          "<pre style='margin:0; white-space:pre-wrap; font-family:inherit;'>" +
          escapeHtml(text) + "</pre>";
      } else {
        content.innerHTML =
          "<pre style='margin:0; white-space:pre-wrap; font-family:inherit;'>" +
          escapeHtml(text) + "</pre>";
      }

      box.setAttribute("aria-busy", "false");
      setPill(termEl, "load", "Loaded", false);

      // required + not checked: 스크롤이 필요 없으면 바로 unlock
      const isRequired = termEl.getAttribute("data-required") === "true";
      const cb = termEl.querySelector(".tc-checkbox");
      if (!cb || cb.checked || !isRequired) return;

      if (box.scrollHeight <= box.clientHeight + 2) {
        cb.disabled = false;
        setHintOk(termEl);
        setPill(termEl, "gate", "Ready", false);
      }
    } catch(e){
      box.setAttribute("aria-busy", "false");
      content.textContent = "Failed to load terms content. Please open 'View details'.";
      setPill(termEl, "load", "Load failed", true);
    }
  }

  function bindGate(termEl){
    const isRequired = termEl.getAttribute("data-required") === "true";
    if (!isRequired) return;

    const cb = termEl.querySelector(".tc-checkbox");
    const box = termEl.querySelector('[data-scrollbox="true"]');
    if (!cb || !box) return;

    // 이미 체크되어 있으면 해제
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

  // init
  const terms = form.querySelectorAll(".term-card[data-term-key]");
  terms.forEach(t => {
    loadExternal(t);
    bindGate(t);
  });

  form.addEventListener("change", (e) => {
    const t = e.target;
    if (!t || t.type !== "checkbox") return;
    updateAcceptButton();
  });

  updateAcceptButton();
})();