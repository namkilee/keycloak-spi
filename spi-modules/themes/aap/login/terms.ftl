<#-- =========================================================
     Terms & Conditions (Multi) – Required Action (Browser)
     Features:
       - Variable sections based on `terms` list
       - External content fetched from term.url
       - Required items: checkbox enabled only after content loaded + scrolled to bottom
       - Accept button enabled only when all required are checked
       - AAP logo applied to top area
     ========================================================= -->

<!DOCTYPE html>
<html lang="${(realm.defaultLocale)!'en'}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${msg("termsTitle","Terms & Conditions")}</title>

  <link rel="stylesheet" href="${url.resourcesPath}/css/agreement.css">
</head>

<body>
  <div class="page">
    <header class="topbar" role="banner">
      <div class="brand" aria-label="AAP Brand">
        <img
          class="brand-logo-aap"
          src="${url.resourcesPath}/img/aap-logo.png"
          alt="AAP AI Assistant Platform"
          onerror="this.style.display='none'"
        />
      </div>
    </header>

    <main class="container" role="main">
      <h1 class="title">${msg("termsTitle","Terms & Conditions")}</h1>
      <p class="subtitle">
        ${msg("termsIntro","To continue, please review and accept the following terms. Required terms must be accepted to proceed.")}
      </p>

      <#if errorKey?? && errorKey?has_content>
        <div class="alert-error" role="alert">${msg(errorKey)}</div>
      <#elseif error?? && error?has_content>
        <div class="alert-error" role="alert">${error}</div>
      </#if>

      <form id="termsForm" method="post" action="${url.loginAction}">
        <#if terms?? && terms?size gt 0>
          <div class="terms" role="list">

            <#list terms as term>
              <#assign termKey = (term.key())!"" >
              <#assign termTitle = (term.title())!termKey >
              <#assign termUrl = (term.url())!"" >
              <#assign isRequired = (term.required())!false >
              <#assign isPreChecked = (missing?? && !missing?seq_contains(termKey)) >

              <section
                class="term-card"
                role="listitem"
                data-term-key="${termKey}"
                data-required="${isRequired?string('true','false')}"
                data-url="${termUrl}"
                data-prechecked="${isPreChecked?string('true','false')}">

                <div class="term-head">
                  <input
                    id="terms-${termKey}"
                    class="terms-checkbox"
                    type="checkbox"
                    name="accepted"
                    value="${termKey}"
                    <#if isPreChecked>checked</#if>
                    <#if isRequired && !isPreChecked>disabled</#if>
                  />

                  <div class="term-main">
                    <div class="term-title-row">
                      <label for="terms-${termKey}" class="term-title">${termTitle}</label>

                      <#if isRequired>
                        <span class="badge badge-required">${msg("required","Required")}</span>
                      <#else>
                        <span class="badge">${msg("optional","Optional")}</span>
                      </#if>
                    </div>

                    <div class="term-meta">
                      <#if termUrl?has_content>
                        <a class="term-link" href="${termUrl}" target="_blank" rel="noopener noreferrer">
                          ${msg("viewDetails","View details")}
                        </a>
                      </#if>

                      <#if isRequired && !isPreChecked>
                        <span class="term-hint" data-hint>
                          ${msg("scrollToEnable","Scroll to the end to enable acceptance.")}
                        </span>
                      </#if>
                    </div>
                  </div>
                </div>

                <#if termUrl?has_content>
                  <div
                    class="term-content"
                    data-scrollbox="true"
                    aria-busy="true"
                    tabindex="0"
                    aria-label="${termTitle}">
                    <div class="term-content-inner" data-content>
                      ${msg("loading","Loading...")}
                    </div>
                    <div class="term-fade"></div>
                  </div>

                  <div class="term-status">
                    <span class="pill" data-pill="load">${msg("statusLoading","Loading terms")}</span>
                    <#if isRequired && !isPreChecked>
                      <span class="pill pill-warn" data-pill="gate">${msg("statusScroll","Scroll required")}</span>
                    </#if>
                  </div>
                <#else>
                  <div class="term-status">
                    <span class="pill pill-warn">
                      ${msg("noDetails","No additional details are available.")}
                    </span>
                  </div>
                </#if>
              </section>
            </#list>

          </div>
        <#else>
          <div class="alert-error" role="alert">
            ${msg("terms.error.noTerms","No terms are configured for this client.")}
          </div>
        </#if>

        <div class="actions">
          <button type="submit" name="action" value="reject" class="btn">
            ${msg("reject","Reject")}
          </button>

          <button id="acceptBtn" type="submit" name="action" value="accept" class="btn btn-primary" disabled>
            ${msg("accept","Accept")}
          </button>
        </div>
      </form>
    </main>

    <footer class="footer" role="contentinfo">
      © 2026 AAP. All rights reserved.
    </footer>
  </div>

  <script src="${url.resourcesPath}/js/agreement.js"></script>
</body>
</html>