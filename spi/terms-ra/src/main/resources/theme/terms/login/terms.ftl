<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Terms & Conditions</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background:#f5f6f8; margin:0; }
    .container { max-width:720px; margin:60px auto; background:#fff; border-radius:8px; padding:32px 36px; box-shadow:0 8px 24px rgba(0,0,0,.08); }
    h1 { margin:0 0 8px 0; font-size:22px; }
    p { color:#555; }
    ul { list-style:none; padding-left:0; margin:24px 0; }
    li { padding:12px 0; border-bottom:1px solid #eee; }
    .meta { color:#777; font-size:13px; margin-left:6px; }
    .optional { font-size:12px; color:#999; margin-left:6px; }
    .error { background:#fdecea; color:#611a15; padding:12px 16px; border-radius:4px; margin-bottom:20px; }
    .actions { margin-top:32px; text-align:right; }
    button { background:#0066ff; color:#fff; border:none; border-radius:4px; padding:10px 18px; font-size:14px; cursor:pointer; }
    button:hover { background:#0053d6; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Terms & Conditions</h1>
    <p>To continue, please review and accept the following terms.</p>

    <#if message?has_content>
      <div class="error">${message.summary}</div>
    </#if>

    <form method="post" action="${url.loginAction}">
      <ul>
        <#list terms as t>
          <li>
            <label>
              <input type="checkbox" name="accepted" value="${t.id}">
              <strong>${t.title}</strong>
              <span class="meta">(version: ${t.version})</span>
              <#if t.url?has_content>
                &nbsp;·&nbsp;<a href="${t.url}" target="_blank" rel="noopener noreferrer">View</a>
              </#if>
              <#if !t.required>
                <span class="optional">(optional)</span>
              </#if>
            </label>
          </li>
        </#list>
      </ul>
      <div class="actions">
        <button type="submit">Accept and continue</button>
      </div>
    </form>
  </div>
</body>
</html>
