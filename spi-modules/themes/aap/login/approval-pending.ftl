<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>승인 대기</title>

  <style>
    body {
      font-family: Arial, Helvetica, sans-serif;
      background-color: #f5f6f8;
      margin: 0;
      padding: 0;
    }

    .container {
      max-width: 480px;
      margin: 80px auto;
      background: #ffffff;
      padding: 32px;
      border-radius: 6px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.08);
    }

    h1 {
      font-size: 20px;
      margin-bottom: 16px;
      color: #111;
    }

    p {
      line-height: 1.5;
      color: #333;
    }

    .service-name {
      font-weight: 700;
      color: #111;
      word-break: break-word;
    }

    .alert {
      margin-top: 16px;
      padding: 12px;
      background: #ffe6e6;
      color: #a40000;
      border-radius: 4px;
      font-size: 14px;
      line-height: 1.5;
    }

    .info {
      margin-top: 16px;
      padding: 12px;
      background: #eef6ff;
      color: #0b4f8a;
      border-radius: 4px;
      font-size: 14px;
      line-height: 1.5;
    }

    .actions {
      margin-top: 24px;
      display: flex;
      flex-direction: column;
      gap: 12px;
    }

    .btn {
      display: inline-block;
      width: 100%;
      padding: 10px 16px;
      text-align: center;
      text-decoration: none;
      border-radius: 4px;
      font-size: 14px;
      cursor: pointer;
      box-sizing: border-box;
    }

    .btn-primary {
      background: #0066cc;
      color: #fff;
      border: none;
    }

    .btn-secondary {
      background: #e0e0e0;
      color: #333;
      border: none;
    }

    .btn-primary:hover {
      background: #0057ad;
    }

    .btn-secondary:hover {
      background: #d5d5d5;
    }

    form {
      margin: 0;
    }

    .help-text {
      margin-top: 18px;
      font-size: 12px;
      color: #666;
      line-height: 1.5;
    }
  </style>
</head>

<body>
  <div class="container">
    <h1>관리자 승인 대기</h1>

    <p>
      <span class="service-name">${clientName!(clientId!"")}</span> 서비스는 현재 승인 대기 상태입니다.
      <br />
      관리자 승인이 완료된 후 아래 버튼을 눌러 계속 진행해 주세요.
    </p>

    <#if approvalStatus?? && approvalStatus == "REJECTED">
      <div class="info">
        현재 요청은 승인 거절 상태입니다. 자세한 내용은 관리자 또는 승인 포털에서 확인해 주세요.
      </div>
    <#else>
      <div class="info">
        아직 승인이 완료되지 않았습니다. 승인이 완료된 뒤 다시 확인해 주세요.
      </div>
    </#if>

    <#if message?has_content && message.summary?has_content>
      <div class="alert">
        ${message.summary}
      </div>
    </#if>

    <div class="actions">
      <#if portalUrl?? && portalUrl?has_content>
        <a
          class="btn btn-secondary"
          href="${portalUrl}"
          target="_blank"
          rel="noopener noreferrer"
        >
          승인 포털로 이동
        </a>
      </#if>

      <form action="${url.loginAction}" method="post">
        <input type="hidden" name="action" value="retry" />
        <button class="btn btn-primary" type="submit">
          승인 상태 다시 확인
        </button>
      </form>
    </div>

    <div class="help-text">
      관리자가 승인하지 않은 경우 이 화면이 계속 표시될 수 있습니다.
    </div>
  </div>
</body>
</html>