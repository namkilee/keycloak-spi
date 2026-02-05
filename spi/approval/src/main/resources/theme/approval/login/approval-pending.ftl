<#-- theme/approval/login/approval-pending.ftl -->
<#import "template.ftl" as layout>

<@layout.registrationLayout displayInfo=false; section>
  <#if section = "header">
    승인 대기
  <#elseif section = "form">
    <div class="kc-form-group">
      <p>
        <strong>${clientId!""}</strong> 서비스는 현재 승인 대기 상태입니다.<br/>
        승인 완료 후 아래 버튼을 눌러 계속 진행하세요.
      </p>

      <#-- 에러 메시지 -->
      <#if message?has_content>
        <div class="alert alert-error">${message.summary}</div>
      </#if>

      <div style="margin-top:16px;">
        <a class="btn btn-secondary" href="https://approval-portal.example.com" target="_blank" rel="noopener">
          승인 포털로 이동
        </a>
      </div>

      <form action="${url.loginAction}" method="post" style="margin-top:16px;">
        <button class="btn btn-primary" type="submit">
          승인 완료 후 계속하기
        </button>
      </form>
    </div>
  </#if>
</@layout.registrationLayout>
