# Approval Service 개발 작업 명령서

## 1. 작업 개요

Keycloak 로그인 과정에서 `terms` Required Action 이후 `approval`
Required Action이 수행되도록 구성한다.

`approval` Required Action은 **외부 서비스를 실시간 조회하지 않고**,
Keycloak 사용자 attribute에 저장된 승인 상태만 확인하여 로그인 허용
여부를 결정한다.

따라서 외부 승인 서비스의 역할은 다음과 같다.

1.  특정 client에 대한 사용자 승인 대기 목록 관리
2.  관리자 승인 / 거절 처리
3.  client별 자동 승인 규칙(auto approve rule) 관리
4.  승인 결과를 Keycloak 사용자 attribute에 반영
5.  Keycloak 로그인 경로에는 직접 개입하지 않음

------------------------------------------------------------------------

# 2. 시스템 구조

External Approval Service - 승인 정책 관리 - 자동 승인 규칙 관리 -
관리자 승인 / 거절 처리 - Keycloak 사용자 attribute 동기화

Keycloak - terms Required Action - approval Required Action -
approval.`<clientId>`{=html} attribute 로 로그인 허용 여부 판단

Keycloak 로그인 경로에서는 외부 서비스 호출을 하지 않는다.

------------------------------------------------------------------------

# 3. Keycloak 연동 방식

## 3.1 승인 상태 저장 방식

Keycloak 사용자 attribute 에 아래 형식으로 저장한다.

approval.`<clientId>`{=html} = APPROVED \| PENDING \| REJECTED

예시

approval.client-a = APPROVED\
approval.client-b = PENDING\
approval.client-c = REJECTED

------------------------------------------------------------------------

## 3.2 승인 상태 의미

APPROVED : 로그인 허용\
PENDING : 승인 대기 화면 표시\
REJECTED : 접근 거절

------------------------------------------------------------------------

## 3.3 포털 URL

Keycloak client attribute 로 아래 값을 사용할 수 있다.

approval_portal_url

이는 Keycloak approval 화면에서 승인 포털 이동 버튼으로 사용된다.

------------------------------------------------------------------------

# 4. 외부 승인 서비스 책임

외부 승인 서비스는 다음 기능을 제공해야 한다.

## 4.1 승인 요청 관리

사용자별 client 승인 상태 관리

가능해야 하는 기능

-   client별 승인 대기 목록 조회
-   사용자 승인 상태 조회
-   승인 요청 생성
-   승인 이력 저장

------------------------------------------------------------------------

## 4.2 관리자 승인 처리

관리자가 승인 처리 시

1.  DB 상태 변경
2.  감사 로그 기록
3.  Keycloak 사용자 attribute 갱신

------------------------------------------------------------------------

## 4.3 관리자 거절 처리

관리자가 거절 처리 시

1.  DB 상태 변경
2.  감사 로그 기록
3.  Keycloak attribute 를 REJECTED 로 갱신

------------------------------------------------------------------------

## 4.4 자동 승인 규칙 관리

client별 auto approve rule 관리

예시 규칙

client: client-a\
rule: department == "People"

규칙이 만족되면 승인 상태는 자동으로 APPROVED

------------------------------------------------------------------------

# 5. 데이터 모델

## 5.1 approval_requests

사용자별 client 승인 상태 저장

주요 컬럼

-   id
-   realm_name
-   client_id
-   user_id
-   username
-   email
-   status
-   requested_at
-   decided_at
-   decided_by
-   decision_reason
-   source
-   created_at
-   updated_at

Unique Key

(realm_name, client_id, user_id)

------------------------------------------------------------------------

## 5.2 auto_approve_rules

client별 자동 승인 규칙

주요 컬럼

-   id
-   realm_name
-   client_id
-   field_name
-   operator
-   expected_value
-   enabled
-   priority
-   description
-   created_at
-   updated_at

------------------------------------------------------------------------

## 5.3 approval_audit_logs

승인 처리 이력

주요 컬럼

-   id
-   realm_name
-   client_id
-   user_id
-   action
-   actor_type
-   actor_id
-   before_status
-   after_status
-   message
-   created_at

------------------------------------------------------------------------

# 6. API 설계

## 승인 요청 생성

POST /api/v1/approval-requests/ensure

예시 요청

{ "realmName": "myrealm", "clientId": "client-a", "user": { "id":
"user-id", "username": "hong", "email": "hong@example.com" } }

------------------------------------------------------------------------

## 승인 대기 목록 조회

GET /api/v1/approval-requests

------------------------------------------------------------------------

## 승인 처리

POST /api/v1/approval-requests/{id}/approve

------------------------------------------------------------------------

## 거절 처리

POST /api/v1/approval-requests/{id}/reject

------------------------------------------------------------------------

# 7. Keycloak 동기화

외부 승인 서비스는 Keycloak Admin API를 사용해 사용자 attribute를
갱신한다.

예시

{ "attributes": { "approval.client-a": \["APPROVED"\] } }

주의

기존 attribute를 덮어쓰지 말고 병합 업데이트 해야 한다.

------------------------------------------------------------------------

# 8. 자동 승인 규칙 엔진

지원 연산자

EQUALS\
IN\
EXISTS

평가 방식

1.  규칙 priority 순 평가
2.  첫 매칭 즉시 승인
3.  매칭 없으면 PENDING

------------------------------------------------------------------------

# 9. 승인 처리 흐름

자동 승인

사용자 접근 → 규칙 평가 → 승인 → Keycloak 동기화

관리자 승인

관리자 승인 → DB 업데이트 → Keycloak attribute 업데이트

------------------------------------------------------------------------

# 10. 운영 정책

승인 정책 원본

External Approval Service DB

로그인 판정 원본

Keycloak user attribute

------------------------------------------------------------------------

# 11. 비기능 요구사항

-   외부 서비스 장애가 로그인 장애로 이어지면 안 됨
-   승인 처리 감사 로그 기록 필요
-   Keycloak과 외부 서비스 상태 추적 가능해야 함

------------------------------------------------------------------------

# 12. 권장 구현 순서

1단계\
approval_requests 테이블 + 승인 API

2단계\
Keycloak Admin API 연동

3단계\
auto approve rule 구현

4단계\
관리 UI 및 재동기화 기능

------------------------------------------------------------------------

# 13. 완료 기준

-   승인 대기 목록 조회 가능
-   관리자 승인/거절 가능
-   자동 승인 규칙 동작
-   Keycloak attribute 동기화 성공
-   approval Required Action 정상 동작
