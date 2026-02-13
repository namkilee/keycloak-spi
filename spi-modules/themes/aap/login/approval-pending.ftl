<#-- theme/approval/login/approval-pending.ftl -->
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8" />
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
    }

    p {
      line-height: 1.5;
      color: #333;
    }

    .alert {
      margin-top: 16px;
      padding: 12px;
      background: #ffe6e6;
      color: #a40000;
      border-radius: 4px;
      font-size: 14px;
    }

    .actions {
      margin-top: 24px;
      display: flex;
      flex-direction: column;
      gap: 12px;
    }

    .btn {
      display: inline-block;
      padding: 10px 16px;
      text-align: center;
      text-decoration: none;
      border-radius: 4px;
      font-size: 14px;
      cursor: pointer;
    }

    .btn-primary {
      background: #0066cc;
      color: #fff;
      border: none;
    }

    .btn-secondary {
      background: #e0e0e0;
      color: #333;
    }
  </style>
</head>

<body>
  <div class="container">
    <h1>승인 대기</h1>

    <p>
      <strong>${clientId!""}</strong> 서비스는 현재 승인 대기 상태입니다.<br/>
      승인이 완료된 후 아래 버튼을 눌러 계속 진행하세요.
    </p>

    <#-- 에러 메시지 -->
    <#if message?has_content>
      <div class="alert">
        ${message.summary}
      </div>
    </#if>

    <div class="actions">
      <a
        class="btn btn-secondary"
        href="https://approval-portal.example.com"
        target="_blank"
        rel="noopener"
      >
        승인 포털로 이동
      </a>

      <form action="${url.loginAction}" method="post">
        <button class="btn btn-primary" type="submit">
          승인 완료 후 계속하기
        </button>
      </form>
    </div>
  </div>
</body>
</html>
