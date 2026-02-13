<#-- =========================================================
     Terms & Conditions (Multi) – Required Action (Desktop)
     Data from SPI:
       - terms    : List<Term>
       - missing  : List<String>   (missing REQUIRED term keys only)
       - errorKey : String (i18n key)  [optional]
       - error    : String          [optional legacy]
     Notes:
       - Auto-escaping is ON
       - MUST post to ${url.loginAction}
     ========================================================= -->

<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>${msg("termsTitle","Terms & Conditions")}</title>

  <style>
    body {
      font-family: Arial, sans-serif;
      background: #f5f6f8;
      margin: 0;
      padding: 0;
      color: #1f2328;
    }

    .container {
      width: 820px;              /* desktop fixed width */
      margin: 64px auto;
      background: #ffffff;
      border-radius: 10px;
      box-shadow: 0 10px 26px rgba(0,0,0,0.10);
      padding: 28px 32px;
    }

    h1 {
      margin: 0 0 10px 0;
      font-size: 22px;
      font-weight: 700;
    }

    .subtitle {
      margin: 0 0 20px 0;
      color: #5a6472;
      line-height: 1.5;
      font-size: 14px;
    }

    .alert-error {
      background: #fdecea;
      border: 1px solid rgba(183, 28, 28, .20);
      color: #8a1c1c;
      padding: 12px 14px;
      border-radius: 8px;
      margin: 14px 0 18px 0;
      font-size: 14px;
    }

    .terms {
      border-top: 1px solid #e7e9ee;
      margin-top: 10px;
    }

    .term {
      padding: 14px 0;
      border-bottom: 1px solid #e7e9ee;
      display: flex;
      gap: 12px;
      align-items: flex-start;
    }

    .term:last-child {
      border-bottom: none;
    }

    .term input[type="checkbox"] {
      width: 18px;
      height: 18px;
      margin-top: 2px;
    }

    .term-main {
      flex: 1;
    }

    .term-title-row {
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .term-title {
      font-weight: 700;
      font-size: 14px;
      color: #111827;
    }

    .badge {
      font-size: 12px;
      padding: 2px 8px;
      border-radius: 999px;
      border: 1px solid rgba(0,0,0,.12);
      background: #f7f7f7;
      color: #4b5563;
    }

    .badge-required {
      background: #fff5f5;
      border-color: rgba(183, 28, 28, .25);
      color: #8a1c1c;
    }

    .term-link {
      display: inline-block;
      margin-top: 6px;
      font-size: 13px;
      color: #1976d2;
      text-decoration: none;
    }

    .term-link:hover {
      text-decoration: underline;
    }

    .actions {
      margin-top: 22px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    .btn {
      border: 1px solid rgba(0,0,0,.14);
      background: #ffffff;
      color: #111827;
      padding: 10px 18px;
      border-radius: 8px;
      cursor: pointer;
      font-size: 14px;
    }

    .btn-primary {
      background: #1976d2;
      border-color: #1976d2;
      color: #ffffff;
    }

    .btn:focus {
      outline: 3px solid rgba(25, 118, 210, .25);
      outline-offset: 2px;
    }
  </style>
</head>

<body>
  <div class="container">
    <h1>${msg("termsTitle","Terms & Conditions")}</h1>
    <p class="subtitle">
      ${msg("termsIntro","To continue, please review and accept the following terms. Required terms must be accepted to proceed.")}
    </p>

    <#-- i18n errorKey 우선, 없으면 legacy error -->
    <#if errorKey?? && errorKey?has_content>
      <div class="alert-error">${msg(errorKey)}</div>
    <#elseif error?? && error?has_content>
      <div class="alert-error">${error}</div>
    </#if>

    <form method="post" action="${url.loginAction}">
      <#if terms?? && terms?size gt 0>
        <div class="terms">
          <#list terms as term>
            <#assign termKey = (term.key())!"" >
            <#assign termTitle = (term.title())!termKey >
            <#assign termUrl = (term.url())!"" >

            <#-- 핵심: boolean으로 유지 -->
            <#assign isRequired = (term.required())!false >

            <div class="term">
              <input
                id="tc-${termKey}"
                type="checkbox"
                name="accepted"
                value="${termKey}"
                <#-- missing는 "누락된 required key"만 온다: missing에 없으면 기존에 체크했던 것으로 간주 -->
                <#if missing?? && !missing?seq_contains(termKey)>
                  checked
                </#if>
              />

              <div class="term-main">
                <div class="term-title-row">
                  <label for="tc-${termKey}" class="term-title">${termTitle}</label>

                  <#if isRequired>
                    <span class="badge badge-required">${msg("required","Required")}</span>
                  <#else>
                    <span class="badge">${msg("optional","Optional")}</span>
                  </#if>
                </div>

                <#if termUrl?has_content>
                  <a class="term-link" href="${termUrl}" target="_blank" rel="noopener noreferrer">
                    ${msg("viewDetails","View details")}
                  </a>
                </#if>
              </div>
            </div>
          </#list>
        </div>
      <#else>
        <div class="alert-error">
          ${msg("terms.error.noTerms","No terms are configured for this client.")}
        </div>
      </#if>

      <div class="actions">
        <button type="submit" name="action" value="reject" class="btn">
          ${msg("reject","Reject")}
        </button>

        <button type="submit" name="action" value="accept" class="btn btn-primary">
          ${msg("accept","Accept")}
        </button>
      </div>
    </form>
  </div>
</body>
</html>
