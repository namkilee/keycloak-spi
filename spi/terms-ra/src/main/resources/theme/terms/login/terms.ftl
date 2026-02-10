<#-- =========================================================
     Terms & Conditions (Multi) - Production-ish
     Provided by SPI:
       - terms   : List<Term> (record/class; access via methods)
       - missing : List<String> (missing REQUIRED keys only)
       - error   : String
     Note:
       - Auto-escaping is ON (HTML output format), so DO NOT use ?html.
     ========================================================= -->

<!DOCTYPE html>
<html class="${properties.kcHtmlClass!}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${msg("termsTitle","Terms & Conditions")}</title>

  <#-- Use Keycloak theme resources if available -->
  <link rel="icon" href="${url.resourcesPath}/img/favicon.ico">
  <link rel="stylesheet" href="${url.resourcesPath}/css/login.css">
  <style>
    /* Lightweight additions on top of Keycloak's login.css */
    .tc-page {
      max-width: 760px;
      margin: 0 auto;
    }
    .tc-card {
      background: var(--pf-v5-global--BackgroundColor--100, #fff);
      border-radius: 12px;
      box-shadow: 0 10px 30px rgba(0,0,0,.08);
      padding: 24px;
    }
    .tc-subtitle {
      margin-top: 8px;
      color: #555;
      line-height: 1.5;
    }

    .tc-alert {
      border-radius: 10px;
      padding: 12px 14px;
      margin: 16px 0;
    }
    .tc-alert--error {
      background: #fdecea;
      color: #8a1c1c;
      border: 1px solid rgba(183, 28, 28, .2);
    }
    .tc-alert--info {
      background: #eef6ff;
      color: #0b3d91;
      border: 1px solid rgba(25, 118, 210, .18);
    }

    .tc-toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
      justify-content: space-between;
      margin: 18px 0 10px;
    }
    .tc-toolbar .tc-actions-left {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
    }

    .tc-btn {
      appearance: none;
      border: 1px solid rgba(0,0,0,.12);
      background: #fff;
      color: #222;
      padding: 10px 12px;
      border-radius: 10px;
      cursor: pointer;
      font-size: 14px;
      line-height: 1;
    }
    .tc-btn:focus {
      outline: 3px solid rgba(25,118,210,.25);
      outline-offset: 2px;
    }
    .tc-btn--primary {
      background: #1976d2;
      border-color: #1976d2;
      color: #fff;
    }
    .tc-btn--ghost {
      background: transparent;
    }

    .tc-list {
      margin: 0;
      padding: 0;
      list-style: none;
      border-top: 1px solid rgba(0,0,0,.08);
    }
    .tc-item {
      padding: 14px 6px;
      border-bottom: 1px solid rgba(0,0,0,.08);
      display: grid;
      grid-template-columns: 24px 1fr;
      gap: 12px;
      align-items: start;
    }

    .tc-title-row {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
    }
    .tc-title {
      font-weight: 700;
      color: #111;
    }
    .tc-badge {
      display: inline-flex;
      align-items: center;
      padding: 2px 8px;
      border-radius: 999px;
      font-size: 12px;
      border: 1px solid rgba(0,0,0,.12);
      color: #444;
      background: #f7f7f7;
    }
    .tc-badge--required {
      color: #8a1c1c;
      border-color: rgba(183, 28, 28, .25);
      background: #fff5f5;
    }

    .tc-meta {
      margin-top: 6px;
      font-size: 13px;
      color: #555;
      line-height: 1.4;
    }
    .tc-link {
      display: inline-block;
      margin-top: 6px;
      font-size: 13px;
      text-decoration: none;
      color: #1976d2;
    }
    .tc-link:hover { text-decoration: underline; }

    .tc-footer {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      justify-content: space-between;
      align-items: center;
      margin-top: 18px;
      padding-top: 14px;
    }

    .tc-note {
      font-size: 12px;
      color: #666;
    }

    /* Make checkbox easier to hit on mobile */
    input[type="checkbox"] {
      width: 18px;
      height: 18px;
      margin-top: 2px;
    }

    @media (max-width: 520px) {
      .tc-card { padding: 18px; }
      .tc-footer { flex-direction: column-reverse; align-items: stretch; }
      .tc-footer .tc-btn { width: 100%; justify-content: center; }
    }
  </style>
</head>

<body class="${properties.kcBodyClass!}">
  <div class="kc-login">
    <div class="kc-login__container tc-page">
      <div class="tc-card" role="main" aria-labelledby="tc-title">
        <h1 id="tc-title" class="${properties.kcFormHeaderClass!}">
          ${msg("termsTitle","Terms & Conditions")}
        </h1>

        <p class="tc-subtitle">
          ${msg("termsIntro","To continue, please review and accept the following terms. Required terms must be accepted to proceed.")}
        </p>

        <#-- Error message when required terms are missing -->
        <#if error?? && error?has_content>
          <div class="tc-alert tc-alert--error" role="alert" aria-live="polite">
            ${error}
          </div>
        </#if>

        <form method="post" id="tc-form" novalidate>
          <#-- Terms list -->
          <#if terms?? && terms?size gt 0>
            <#-- compute required keys for client-side validation -->
            <#assign requiredKeys = []>
            <#list terms as t>
              <#if ((t.required()?c)!"false") == "true">
                <#assign requiredKeys = requiredKeys + [ (t.key())!"" ]>
              </#if>
            </#list>

            <div class="tc-toolbar" aria-label="Terms controls">
              <div class="tc-actions-left">
                <button type="button" class="tc-btn tc-btn--ghost" id="btn-accept-required">
                  ${msg("acceptRequired","Accept required")}
                </button>
                <button type="button" class="tc-btn tc-btn--ghost" id="btn-accept-all">
                  ${msg("acceptAll","Accept all")}
                </button>
                <button type="button" class="tc-btn" id="btn-clear">
                  ${msg("clearSelection","Clear")}
                </button>
              </div>

              <div class="tc-note" id="tc-status" aria-live="polite"></div>
            </div>

            <ul class="tc-list" aria-describedby="tc-status">
              <#list terms as term>
                <#assign termKey = (term.key())!"" >
                <#assign termTitle = (term.title())!termKey >
                <#assign termUrl = (term.url())!"" >
                <#assign termRequiredStr = (term.required()?c)!"false" >
                <#assign isRequired = (termRequiredStr == "true")>

                <li class="tc-item">
                  <div>
                    <input
                      id="tc-${termKey}"
                      type="checkbox"
                      name="accepted"
                      value="${termKey}"
                      <#-- missing contains ONLY missing REQUIRED keys.
                           If current key is not in missing, user had checked it previously. -->
                      <#if missing?? && (missing?seq_contains(termKey) == false)>
                        checked
                      </#if>
                      <#if isRequired>
                        data-required="true"
                      </#if>
                    />
                  </div>

                  <div>
                    <div class="tc-title-row">
                      <label for="tc-${termKey}" class="tc-title">${termTitle}</label>

                      <#if isRequired>
                        <span class="tc-badge tc-badge--required">${msg("required","Required")}</span>
                      <#else>
                        <span class="tc-badge">${msg("optional","Optional")}</span>
                      </#if>
                    </div>

                    <div class="tc-meta">
                      <#if termUrl?has_content>
                        <a class="tc-link" href="${termUrl}" target="_blank" rel="noopener noreferrer">
                          ${msg("viewDetails","View details")}
                        </a>
                      <#else>
                        <span>${msg("detailsProvidedSeparately","Details provided separately.")}</span>
                      </#if>
                    </div>
                  </div>
                </li>
              </#list>
            </ul>

            <div class="tc-footer">
              <button type="submit" name="action" value="reject" class="tc-btn" formnovalidate>
                ${msg("reject","Reject")}
              </button>

              <button type="submit" name="action" value="accept" class="tc-btn tc-btn--primary" id="btn-submit-accept">
                ${msg("accept","Accept")}
              </button>
            </div>

            <p class="tc-note" style="margin-top:10px;">
              ${msg("termsNote","You can withdraw consent later where applicable. Required terms are necessary to use the service.")}
            </p>

            <script>
              (function () {
                const form = document.getElementById('tc-form');
                const status = document.getElementById('tc-status');
                const btnAccept = document.getElementById('btn-submit-accept');
                const btnAcceptRequired = document.getElementById('btn-accept-required');
                const btnAcceptAll = document.getElementById('btn-accept-all');
                const btnClear = document.getElementById('btn-clear');

                const checkboxes = Array.from(form.querySelectorAll('input[type="checkbox"][name="accepted"]'));
                const required = checkboxes.filter(cb => cb.dataset.required === 'true');

                function countChecked(list) {
                  return list.reduce((acc, cb) => acc + (cb.checked ? 1 : 0), 0);
                }

                function validate() {
                  const requiredChecked = countChecked(required);
                  const requiredTotal = required.length;

                  const allChecked = countChecked(checkboxes);
                  const allTotal = checkboxes.length;

                  // Disable Accept when any required unchecked
                  const ok = (requiredChecked === requiredTotal);
                  btnAccept.disabled = !ok;
                  btnAccept.setAttribute('aria-disabled', String(!ok));

                  status.textContent =
                    (requiredTotal > 0)
                      ? ('Required: ' + requiredChecked + '/' + requiredTotal + ' · Total: ' + allChecked + '/' + allTotal)
                      : ('Total: ' + allChecked + '/' + allTotal);

                  return ok;
                }

                function setAll(flag, onlyRequired) {
                  checkboxes.forEach(cb => {
                    if (onlyRequired && cb.dataset.required !== 'true') return;
                    cb.checked = flag;
                  });
                  validate();
                }

                checkboxes.forEach(cb => cb.addEventListener('change', validate));

                btnAcceptAll.addEventListener('click', function () { setAll(true, false); });
                btnAcceptRequired.addEventListener('click', function () { setAll(true, true); });
                btnClear.addEventListener('click', function () { setAll(false, false); });

                form.addEventListener('submit', function (e) {
                  const action = (new FormData(form).get('action') || '').toString();
                  if (action === 'accept' && !validate()) {
                    e.preventDefault();
                    // Let server-side error handle too, but give instant feedback
                    alert('Please accept all required terms to continue.');
                  }
                });

                // initial
                validate();
              })();
            </script>

          <#else>
            <div class="tc-alert tc-alert--error" role="alert">
              ${msg("noTermsConfigured","No terms are configured for this client.")}
            </div>

            <div class="tc-footer">
              <button type="submit" name="action" value="reject" class="tc-btn">
                ${msg("back","Back")}
              </button>
            </div>
          </#if>
        </form>

      </div>
    </div>
  </div>
</body>
</html>
