<#-- =========================================================
     Terms & Conditions (Multi)
     Data provided by SPI:
       - terms   : List<Term>  (record/class; access via methods)
       - missing : List<String>
       - error   : String
     Note:
       - Auto-escaping is ON (HTML output format), so DO NOT use ?html.
     ========================================================= -->

<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Terms & Conditions</title>
  <style>
    body { font-family: Arial, sans-serif; background: #f7f7f7; }
    .container { max-width: 640px; margin: 60px auto; background: #fff; padding: 32px; border-radius: 8px;
                 box-shadow: 0 4px 12px rgba(0,0,0,0.1); }
    h1 { margin-top: 0; font-size: 22px; }
    .term { margin-bottom: 16px; padding-bottom: 12px; border-bottom: 1px solid #eee; }
    .term:last-child { border-bottom: none; }
    .term-title { font-weight: bold; }
    .required { color: #d32f2f; font-size: 12px; margin-left: 6px; }
    .optional { color: #666; font-size: 12px; margin-left: 6px; }
    .term-link { display: block; margin-top: 6px; font-size: 13px; }
    .error { background: #fdecea; color: #b71c1c; padding: 12px; border-radius: 4px; margin-bottom: 20px; }
    .actions { margin-top: 24px; display: flex; justify-content: space-between; }
    button { padding: 10px 18px; border-radius: 4px; border: none; cursor: pointer; font-size: 14px; }
    .btn-accept { background: #1976d2; color: #fff; }
    .btn-reject { background: #e0e0e0; color: #333; }
  </style>
</head>
<body>

<div class="container">
  <h1>Terms & Conditions</h1>

  <p>
    To continue, please review and accept the following terms.
    Required terms must be accepted to proceed.
  </p>

  <#-- Error message when required terms are missing -->
  <#if error?? && error?has_content>
    <div class="error">
      ${error}
    </div>
  </#if>

  <form method="post">

    <#if terms?? && terms?size gt 0>
      <#list terms as term>
        <#-- Java record/class safe access via methods -->
        <#assign termKey = (term.key())!"" >
        <#assign termTitle = (term.title())!termKey >
        <#assign termUrl = (term.url())!"" >
        <#assign termRequiredStr = (term.required()?c)!"false" >

        <div class="term">
          <label>
            <input
              type="checkbox"
              name="accepted"
              value="${termKey}"
              <#-- missing contains ONLY missing REQUIRED keys.
                   If current key is not in missing, user had checked it previously. -->
              <#if missing?? && (missing?seq_contains(termKey) == false)>
                checked
              </#if>
            />
            <span class="term-title">${termTitle}</span>

            <#if termRequiredStr == "true">
              <span class="required">(required)</span>
            <#else>
              <span class="optional">(optional)</span>
            </#if>
          </label>

          <#if termUrl?has_content>
            <a class="term-link" href="${termUrl}" target="_blank" rel="noopener noreferrer">
              View details
            </a>
          <#else>
            <span class="term-link">(Details provided separately)</span>
          </#if>
        </div>
      </#list>
    <#else>
      <div class="error">
        No terms are configured for this client.
      </div>
    </#if>

    <div class="actions">
      <button type="submit" name="action" value="reject" class="btn-reject">
        Reject
      </button>

      <button type="submit" name="action" value="accept" class="btn-accept">
        Accept
      </button>
    </div>

  </form>
</div>

</body>
</html>
