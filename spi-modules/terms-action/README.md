좋아.
그럼 **Keycloak용 Terms / Agreements Required Action SPI** 를 새로 설계할 수 있을 정도로, 요구사항을 **기능/데이터/동작/운영/비기능** 기준으로 명확하게 정리해줄게.

아래 문서는 그대로 **설계서 초안 / 구현 명세** 로 써도 될 수준으로 잡아볼게.

---

# 1. 목표

본 SPI의 목적은 Keycloak 로그인 과정에서 사용자에게 필요한 약관을 표시하고, 사용자의 동의 여부를 기록하며, 약관 버전이 변경되었을 때 재동의를 강제하는 것이다.

이 SPI는 다음을 만족해야 한다.

* 여러 개의 약관을 지원한다.
* 약관마다 필수/선택 여부를 가질 수 있다.
* 약관마다 버전을 가진다.
* 사용자가 이미 동의한 약관 버전과 현재 버전을 비교하여 재동의 필요 여부를 판단한다.
* Client 또는 Client Scope 기반으로 약관 구성이 달라질 수 있다.
* 운영자가 Terraform 등 외부 설정 도구로 약관 구성을 관리할 수 있어야 한다.
* Keycloak 로그인 플로우에 자연스럽게 통합되어야 한다.

---

# 2. 범위

## 포함 범위

이 SPI는 다음을 포함한다.

* Required Action Provider 구현
* 약관 설정 조회
* 재동의 필요 여부 판단
* 약관 화면 렌더링
* 사용자 동의 결과 저장
* 필수 약관 검증
* 약관 버전 비교 로직
* Client/Scope 별 약관 구성 반영

## 제외 범위

이 SPI는 다음을 직접 포함하지 않는다.

* 약관 원문 자체의 CMS 관리 기능
* 약관 문서 편집 UI
* 법무 승인 워크플로우
* 약관 PDF 생성
* 외부 감사 시스템 연동
* 동의 이력의 장기 보관용 별도 데이터베이스

단, 추후 확장을 고려하여 인터페이스 수준으로는 열어둘 수 있다.

---

# 3. 핵심 개념

## 3.1 Term

하나의 약관 항목.

예:

* 서비스 이용약관
* 개인정보 처리방침
* 마케팅 수신 동의

## 3.2 Terms Bundle

특정 로그인 시점에 사용자에게 적용되는 약관 집합.

예:

* client A 에 로그인 시: privacy + service
* client B 에 로그인 시: privacy + service + marketing

## 3.3 Current Version

현재 시스템이 요구하는 약관 버전.

## 3.4 Accepted Version

사용자가 마지막으로 동의한 약관 버전.

## 3.5 Re-consent

사용자가 동의했던 버전과 현재 버전이 다를 경우 다시 동의받는 행위.

---

# 4. 기능 요구사항

# 4.1 로그인 시 약관 동의 강제

시스템은 Keycloak 로그인 과정에서 Required Action 으로 동작해야 한다.

동작은 다음과 같다.

1. 사용자가 인증에 성공한다.
2. SPI는 현재 로그인 컨텍스트에 적용되는 약관 목록을 조회한다.
3. 필수 약관 중 하나라도 미동의 또는 구버전 동의 상태이면 약관 동의 화면을 표시한다.
4. 사용자가 필요한 약관에 동의해야만 로그인 완료가 가능하다.

---

# 4.2 다중 약관 지원

시스템은 한 번의 로그인에서 여러 약관을 동시에 처리할 수 있어야 한다.

각 약관은 독립적인 식별자를 가진다.

예:

* `service`
* `privacy`
* `marketing`
* `security`

각 약관은 별도의 required 여부, version, title, content source 를 가질 수 있어야 한다.

---

# 4.3 필수 / 선택 약관 구분

각 약관은 `required=true|false` 를 가질 수 있어야 한다.

* 필수 약관은 체크하지 않으면 로그인 진행 불가
* 선택 약관은 체크하지 않아도 로그인 진행 가능

단, 선택 약관도 사용자가 체크하면 기록은 저장할 수 있어야 한다.

---

# 4.4 버전 기반 재동의

각 약관은 버전을 가져야 한다.

예:

* `2026-03-01`
* `v2`
* `2026.1`

시스템은 사용자의 동의 기록과 현재 약관 버전을 비교하여 다음을 판단해야 한다.

* 동의 기록 없음 → 동의 필요
* 동의 기록은 있으나 버전 다름 → 재동의 필요
* 동의 기록 있고 버전 동일 → 재동의 불필요

버전 비교는 기본적으로 문자열 동등 비교로 충분하다.
즉, 정렬 가능한 semantic version 비교가 아니라 **현재 버전 문자열과 사용자 저장 버전 문자열이 일치하는지** 만 판단하면 된다.

---

# 4.5 Client / Client Scope 별 약관 구성

로그인 대상 Client 에 따라 표시되는 약관 집합이 달라질 수 있어야 한다.

약관 구성은 다음 중 최소 하나를 지원해야 한다.

1. Client attribute 기반
2. Client Scope attribute 기반

권장 방향은 **Client Scope 기반** 이다.
이유는 여러 Client 가 공통 약관 구성을 재사용하기 쉽기 때문이다.

최종적으로 SPI는 로그인 시점에 **현재 Client 에 연결된 scope 들을 기준으로 유효한 약관 집합을 계산** 할 수 있어야 한다.

---

# 4.6 약관 구성 병합

하나의 Client 에 여러 scope 가 연결되어 있고, 각 scope 가 약관 구성을 가질 수 있다.

이 경우 SPI는 병합 규칙을 가져야 한다.

최소 요구사항은 아래와 같다.

* 동일 term key 는 하나의 최종 term 으로 병합된다.
* 충돌 시 우선순위 규칙이 있어야 한다.
* 병합 후 최종 Terms Bundle 이 결정된다.

권장 우선순위:

1. 더 높은 `priority`
2. 동일 priority 인 경우 더 구체적인 source 우선
3. 그래도 같으면 deterministic 하게 key/name 기준 정렬

---

# 4.7 약관 표시 순서

화면에 표시되는 약관 순서는 예측 가능해야 한다.

최소 요구사항:

* 필수 약관 먼저
* 선택 약관 나중
* 같은 그룹 내에서는 지정된 order 또는 key 기준 정렬

권장 요구사항:

각 Bundle 또는 Term 에 `display_order` 또는 `priority` 를 둘 수 있어야 한다.

---

# 4.8 약관 내용 제공 방식

약관 본문은 다음 중 하나 이상의 방식으로 제공될 수 있어야 한다.

## 방식 A. 외부 URL

약관 내용이 외부 URL 에 존재한다.

예:

* `https://example.com/terms/privacy.html`

## 방식 B. Keycloak theme template

Keycloak theme 내부 템플릿 또는 정적 파일을 이용한다.

## 방식 C. inline text

간단한 텍스트는 attribute 에 직접 저장할 수 있다.

권장 순위는 다음과 같다.

1. `url`
2. `template`
3. `inline_content`

단, 실제 구현에서는 하나만 먼저 지원하고 확장 가능하게 설계해도 된다.

---

# 4.9 약관 화면 표시

약관 화면은 동적으로 렌더링되어야 한다.

최소 요구사항:

* 약관 목록 표시
* 각 약관 제목 표시
* 필수 여부 표시
* 체크박스 표시
* 제출 버튼 제공
* 필수 약관 미체크 시 제출 불가 또는 서버에서 실패 처리

권장 요구사항:

* 약관 내용을 읽고 스크롤한 뒤 체크 가능
* 모바일/브라우저 대응
* 브랜딩 가능
* 접근성 고려

---

# 4.10 사용자 동의 결과 저장

사용자가 동의한 결과는 사용자별로 저장되어야 한다.

저장 최소 항목:

* term key
* accepted version
* accepted timestamp
* 선택 동의 여부

저장 위치는 기본적으로 **user attributes** 를 사용한다.

예시 저장 방식은 두 가지 중 하나를 택할 수 있다.

## 방식 A. term 별 개별 key 저장

예:

* `terms.accepted.privacy.version = 2026-03-01`
* `terms.accepted.privacy.at = 2026-03-12T10:20:30Z`

## 방식 B. 단일 JSON 저장

예:

* `terms_acceptance = { ...json... }`

운영 단순성과 stale key 문제 방지를 고려하면 **단일 JSON 저장 방식이 권장** 된다.

---

# 4.11 미동의 판별 규칙

사용자에게 약관 화면을 보여줄지 여부는 아래 규칙을 따른다.

어떤 term 이든 다음 중 하나에 해당하면 해당 term 은 동의 필요 상태다.

* 사용자의 동의 기록이 없음
* 저장된 accepted version 이 현재 version 과 다름
* 필수 약관인데 accepted=true 가 아님

최종적으로 **필수 약관 중 하나라도 동의 필요 상태이면 Required Action 을 수행** 해야 한다.

선택 약관에 대해서는 정책 선택이 가능하다.

권장 기본 정책:

* 선택 약관은 처음 노출 시 함께 보여줄 수 있다.
* 하지만 선택 약관 미동의만으로 로그인 차단은 하지 않는다.

---

# 4.12 폼 제출 검증

사용자가 약관 화면에서 제출했을 때 서버는 다음을 반드시 검증해야 한다.

* 현재 시점의 약관 목록 기준으로 검증할 것
* 필수 약관이 모두 체크되었는지 확인할 것
* 클라이언트가 조작한 hidden field 만 믿지 말 것
* 제출 시점과 렌더링 시점의 설정 차이가 있더라도 서버 기준으로 판단할 것

즉, 프론트엔드 체크는 편의 기능일 뿐이고, 최종 판정은 반드시 서버가 해야 한다.

---

# 4.13 동의 후 Required Action 해제

사용자가 필요한 약관에 정상적으로 동의하면 해당 Required Action 은 완료 상태가 되어야 한다.

다음 로그인 시에는 재동의 필요 조건이 없는 한 다시 표시되지 않아야 한다.

---

# 4.14 재동의 트리거

재동의는 최소한 아래 경우에 발생해야 한다.

* term version 변경
* term 이 새롭게 추가됨
* 기존에 선택이었던 약관이 필수로 변경됨

정책적으로 아래도 고려 가능하나 필수는 아니다.

* title 변경만으로 재동의
* URL 변경만으로 재동의

권장 기본 정책은 **version 이 변경된 경우에만 재동의** 다.

---

# 5. 데이터 요구사항

# 5.1 Term 정의 모델

각 term 은 다음 필드를 가져야 한다.

* `key`: 약관 식별자, 필수, 영문/slug 권장
* `title`: 사용자에게 보이는 제목
* `required`: 필수 여부
* `version`: 현재 약관 버전
* `display_order`: 표시 순서, 선택
* `content_source_type`: `url | template | inline`
* `content_source_value`: 실제 값
* `text_summary`: 요약 텍스트, 선택
* `audience`: 적용 대상 정보, 선택
* `enabled`: 활성 여부, 선택

최소 구현 필수 필드는 다음이다.

* `key`
* `required`
* `version`

권장 필수 필드는 다음이다.

* `key`
* `title`
* `required`
* `version`

---

# 5.2 Terms Bundle 모델

Bundle 은 다음 필드를 가질 수 있어야 한다.

* `source_id`: 어떤 client/scope/config 로부터 생성되었는지
* `priority`: 병합 우선순위
* `terms`: term list

---

# 5.3 User Acceptance 모델

사용자 저장 모델은 최소한 아래 정보가 필요하다.

* `term_key`
* `accepted_version`
* `accepted`
* `accepted_at`

권장 추가 항목:

* `source_client_id`
* `source_scope_ids`
* `locale`
* `ip` 또는 세션 정보는 선택

단, 개인정보/감사 범위를 고려해 과도한 저장은 피한다.

---

# 6. 설정 요구사항

# 6.1 설정 저장 형식

운영성과 stale key 문제를 고려하면, 약관 설정은 **단일 JSON attribute** 로 저장하는 방식을 권장한다.

예:

* `terms_config`

예시 구조:

```json
{
  "priority": 10,
  "terms": {
    "service": {
      "title": "서비스 이용약관",
      "required": true,
      "version": "2026-03-01",
      "display_order": 10,
      "content": {
        "type": "url",
        "value": "https://example.com/terms/service"
      }
    },
    "privacy": {
      "title": "개인정보 처리방침",
      "required": true,
      "version": "2026-03-01",
      "display_order": 20,
      "content": {
        "type": "url",
        "value": "https://example.com/terms/privacy"
      }
    },
    "marketing": {
      "title": "마케팅 수신 동의",
      "required": false,
      "version": "2026-03-01",
      "display_order": 30,
      "content": {
        "type": "template",
        "value": "marketing.ftl"
      }
    }
  }
}
```

---

# 6.2 레거시 attribute 처리

현재 구현은 legacy `terms.<key>.*`/`tc_*` 분산 attribute를 읽지 않는다.

* source of truth: `terms_config` JSON attribute 단일 키
* legacy attribute가 남아 있어도 Required Action 계산에 사용되지 않음


---

# 7. 비기능 요구사항

# 7.1 결정 가능성

같은 설정과 같은 사용자 상태라면 항상 같은 결과가 나와야 한다.

즉:

* 같은 입력 → 같은 Terms Bundle
* 같은 user acceptance → 같은 required action 판단

---

# 7.2 운영 단순성

운영자는 Terraform 등으로 선언한 값만 관리하면 되어야 한다.

권장사항:

* 다수 attribute 대신 단일 JSON attribute 사용
* 수동 삭제 작업 최소화
* stale key 발생 최소화

---

# 7.3 가독성 / 디버깅

로그에는 최소한 다음이 보여야 한다.

* 어떤 client 로 로그인했는지
* 어떤 terms bundle 이 선택되었는지
* 어떤 term 이 미동의/재동의 대상인지
* 어떤 사용자 attribute 가 저장되었는지

단, 민감정보는 로그에 과도하게 남기지 않는다.

---

# 7.4 성능

로그인 시 호출되므로 과도하게 느리면 안 된다.

권장사항:

* client/scope attribute 조회만으로 판단 가능해야 함
* 외부 네트워크 호출은 가급적 피함
* 화면 렌더링 시 외부 URL fetch 는 브라우저에서 처리하더라도 서버 로직은 외부 의존 최소화

---

# 7.5 장애 허용 정책

약관 설정이 비정상일 때 정책을 정해야 한다.

권장 기본 정책:

* 필수 설정 누락 시 로그인 차단 또는 명시적 에러 페이지
* 선택 약관 설정 오류는 무시 가능
* JSON 파싱 실패 시 운영자가 즉시 알 수 있도록 로그 출력

---

# 8. 권장 아키텍처 요구사항

구현은 아래 컴포넌트로 분리하는 것이 바람직하다.

## 8.1 TermsRequiredActionProvider

* Required Action 진입점
* evaluateTriggers
* requiredActionChallenge
* processAction

## 8.2 TermsResolver

* 현재 client / scope 로부터 최종 Terms Bundle 계산

## 8.3 TermsConfigParser

* `terms_config` 단일 JSON attribute 파싱

## 8.4 TermsAcceptanceRepository

* user attribute 로부터 동의 기록 읽기/쓰기

## 8.5 TermsDecisionService

* 어떤 term 이 재동의 대상인지 판단

## 8.6 TermsPageModelBuilder

* FTL 에 넘길 ViewModel 생성

이렇게 나누면 유지보수가 쉬워진다.

---

# 9. 상세 동작 시나리오

# 9.1 로그인 시 약관 필요 없음

조건:

* 적용 대상 term 없음
  또는
* 모든 필수 term 이 현재 버전에 대해 이미 동의됨

결과:

* Required Action 실행 안 함
* 로그인 계속 진행

---

# 9.2 필수 약관 미동의

조건:

* 필수 term 중 동의 기록이 없거나 버전 불일치

결과:

* 약관 화면 표시
* 필수 term 모두 체크 전까지 완료 불가

---

# 9.3 선택 약관만 미동의

정책 선택 가능.

권장 기본:

* 화면에 함께 보여줄 수 있음
* 하지만 미체크여도 로그인 허용 가능

---

# 9.4 약관 버전 변경

조건:

* 기존 accepted version = `2026-01-01`
* current version = `2026-03-01`

결과:

* 재동의 필요
* 화면 다시 표시
* 동의 후 accepted version 갱신

---

# 9.5 새 약관 추가

조건:

* 기존에는 없던 `security` term 이 bundle 에 추가됨

결과:

* 필수면 재동의 화면 표시
* 선택이면 정책에 따라 표시 가능

---

# 10. 예외 상황 요구사항

# 10.1 필수 term 에 version 없음

이 경우는 설정 오류로 간주해야 한다.

권장 처리:

* 에러 로그
* 로그인 차단 또는 명시적 에러 화면

---

# 10.2 필수 term 에 content source 없음

최소 구현에서는 제목만 있어도 체크는 받을 수 있다.
하지만 운영상 바람직하지 않으므로 경고 로그를 남겨야 한다.

---

# 10.3 중복 term key 충돌

여러 source 에서 같은 key 가 들어오면 병합 규칙을 따라야 한다.
충돌 상황은 디버그 로그로 확인 가능해야 한다.

---

# 11. 보안 요구사항

* 약관 수락 여부는 서버에서 최종 검증할 것
* 클라이언트 입력만 믿지 말 것
* 필수 약관 누락 시 절대 통과시키지 말 것
* user attribute 저장 시 term key 와 version 은 sanitize 된 값만 사용할 것
* 화면에 표시하는 title/content 는 XSS 대응을 고려할 것

---

# 12. 권장 저장 전략

운영성과 구현 단순성을 고려한 권장안은 아래와 같다.

## 약관 설정 저장

* Client Scope attribute 의 `terms_config` 단일 JSON

## 사용자 동의 저장

* user attribute 의 `terms_acceptance` 단일 JSON

이렇게 하면:

* stale attribute 문제 감소
* Terraform sync 단순화
* SPI 파싱 단순화
* 버전 비교 및 디버깅 쉬움

---

# 13. MVP 요구사항

최초 구현에서 반드시 필요한 최소 요구사항은 아래다.

* Required Action Provider 동작
* Client/Scope 에서 약관 설정 읽기
* 다중 약관 지원
* 필수/선택 구분
* 버전 기반 재동의
* 사용자 동의 저장
* FTL 화면 렌더링
* 필수 약관 서버 검증

---

# 14. 권장 확장 요구사항

초기 구현 이후 확장 가능한 항목들이다.

* 다국어 title/content
* 감사 로그 저장
* 관리자용 디버그 endpoint
* scope merge 우선순위 세분화
* 약관 동의 이력 다건 보관
* 선택 약관 정책 세분화
* 브라우저에서 약관 스크롤 완료 후 체크 허용

---

# 15. 구현자가 바로 코딩할 수 있게 정리한 최종 요구사항

아주 압축하면 이거야.

## 시스템은

* Keycloak Required Action SPI 로 동작해야 한다.

## 설정은

* Client Scope attribute 의 `terms_config` JSON 에서 읽는다.

## `terms_config` 는

* priority
* terms map
  를 가진다.

## 각 term 은

* key
* title
* required
* version
* display_order
* content(type, value)
  를 가진다.

## 로그인 시

* 현재 client 에 연결된 모든 scope 의 `terms_config` 를 수집한다.
* 병합하여 최종 Terms Bundle 을 만든다.
* 사용자 동의 기록과 비교한다.
* 필수 term 중 미동의/구버전이 있으면 약관 화면을 보여준다.

## 제출 시

* 필수 term 이 모두 체크되었는지 서버에서 검증한다.
* 동의 결과를 user attribute `terms_acceptance` JSON 에 저장한다.
* 현재 version 으로 갱신한다.

## 저장은

* 설정: `terms_config`
* 사용자 동의: `terms_acceptance`

## 기본 정책은

* version 이 바뀌면 재동의
* 필수 약관 미동의 시 로그인 불가
* 선택 약관은 미동의여도 로그인 가능

---

원하면 다음 답변에서 이 requirement 를 바탕으로 바로 구현 가능한 수준의
**Java 클래스 설계 + JSON 스키마 + RequiredAction 흐름도**까지 이어서 정리해줄게.
