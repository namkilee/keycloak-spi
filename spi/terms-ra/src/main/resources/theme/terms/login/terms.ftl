<#-- =========================================================
     Terms & Conditions (Multi) – Required Action
     Data from SPI:
       - terms   : List<Term>
       - missing : List<String>   (missing REQUIRED term keys only)
       - errorKey: String (i18n key)
     Notes:
       - Auto-escaping is ON
       - MUST post to ${url.loginAction}
     ========================================================= -->

<!DOCTYPE html>
<html class="${properties.kcHtmlClass!}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${msg("termsTitle","Terms & Conditions")}</title>

  <link rel="icon" href="${url.resourcesPath}/img/favicon.ico">
  <link rel="stylesheet" href="${url.resourcesPath}/css/login.css">

  <style>
    .terms-container {
      max-width: 720px;
      margin: 0 auto;
    }
    .terms-box {
      background: var(--pf-v5-global--BackgroundColor--100, #fff);
      padding: 24px;
      border-radius: 12px;
      box-shadow: 0 6px 18px rgba(0,0,0,.08);
    }
    .terms-item {
      padding: 14px 0;
      border-bottom: 1px solid rgba(0,0,0,.08);
    }
    .terms-item:last-child {
      border-bottom: none;
    }
    .terms-title {
      font-weight: 600;
    }
    .terms-meta {
      font-size: 13px;
      color: #666;
      margin-top: 4px;
    }
    .badge-required {
      color: #b71c1c;
      font-size: 12px;
      margin-left: 6px;
    }
    .badge-optional {
      color: #666;
      font-size: 12px;
      margin-left: 6px;
    }
    .terms-actions {
      margin-top: 24px;
      display: flex;
      justify-content: space-between;
      gap: 12px;
    }
  </style>
</head>

<body class="${properties.kcBodyClass!}">
<div class="kc-login">
  <div class="kc-login__container terms-container">

    <div class="terms-box">
      <h1 class="${properties.kcFormHeaderClass!}">
        ${msg("termsTitle","Terms & Conditions")}
      </h1>

      <p>
        ${msg(
          "termsIntro",
          "To continue, please review and accept the following terms. Required terms must be accepted."
        )}
      </p>

      <#-- Error message (i18n key) -->
      <#if errorKey?? && errorKey?has_content>
        <div class="${properties.kcFeedbackErrorClass!}">
          ${msg(errorKey)}
        </div>
      </#if>

      <#-- IMPORTANT: action MUST be url.loginAction -->
      <form
        id="kc-terms-form"
        class="${properties.kcFormClass!}"
        method="post"
        action="${url.loginAction}"
      >

        <#if terms?? && terms?size gt 0>
          <#list terms as term>
            <#assign termKey = (term.key())!"" >
            <#assign termTitle = (term.title())!termKey >
            <#assign termUrl = (term.url())!"" >
            <#assign isRequired = (term.required()?c)!"false" == "true" >

            <div class="terms-item">
              <label>
                <input
                  type="checkbox"
                  name="accepted"
                  value="${termKey}"
                  <#-- if not missing, it was previously accepted -->
                  <#if missing?? && !missing?seq_contains(termKey)>
                    checked
                  </#if>
                />

                <span class="terms-title">
                  ${termTitle}
                </span>

                <#if isRequired>
                  <span class="badge-required">
                    (${msg("required","required")})
                  </span>
                <#else>
                  <span class="badge-optional">
                    (${msg("optional","optional")})
                  </span>
                </#if>
              </label>

              <#if termUrl?has_content>
                <div class="terms-meta">
                  <a href="${termUrl}" target="_blank" rel="noopener noreferrer">
                    ${msg("viewDetails","View details")}
                  </a>
                </div>
              </#if>
            </div>
          </#list>
        <#else>
          <div class="${properties.kcFeedbackErrorClass!}">
            ${msg("terms.error.noTerms","No terms are configured.")}
          </div>
        </#if>

        <div class="terms-actions">
          <button
            type="submit"
            name="action"
            value="reject"
            class="${properties.kcButtonDefaultClass!}"
          >
            ${msg("reject","Reject")}
          </button>

          <button
            type="submit"
            name="action"
            value="accept"
            class="${properties.kcButtonPrimaryClass!}"
          >
            ${msg("accept","Accept")}
          </button>
        </div>

      </form>
    </div>

  </div>
</div>
</body>
</html>
