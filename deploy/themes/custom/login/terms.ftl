<#import "template.ftl" as layout>

<@layout.registrationLayout displayInfo=false; section>
  <#if section == "header">
    ${msg("termsTitle")!"Terms & Conditions"}
  <#elseif section == "form">
    <#if message?has_content>
      <div class="alert alert-error">
        <span class="kc-feedback-text">${message.summary}</span>
      </div>
    </#if>

    <form id="kc-terms-form" class="form" action="${url.loginAction}" method="post">
      <div class="kc-form-group">
        <#list terms as term>
          <div class="kc-terms-item">
            <label class="checkbox">
              <input type="checkbox" name="accepted" value="${term.id}"
                <#if missing?has_content && !(missing?seq_contains(term.id))>checked</#if>>
              <strong>${term.title}</strong>
              <#if term.version?has_content>
                <span class="kc-terms-version">(${term.version})</span>
              </#if>
              <#if term.required>
                <span class="kc-terms-required">*</span>
              </#if>
            </label>
            <#if term.url?has_content>
              <div class="kc-terms-link">
                <a href="${term.url}" target="_blank" rel="noopener noreferrer">${term.url}</a>
              </div>
            </#if>
          </div>
        </#list>
      </div>

      <div class="kc-form-group">
        <input class="btn btn-primary btn-block" type="submit" value="${msg("doSubmit")!"Submit"}">
      </div>
    </form>
  </#if>
</@layout.registrationLayout>
