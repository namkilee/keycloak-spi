# Deployment Assets

배포 보조 리소스 디렉터리다.

## 포함 항목

- `docker/`
  - 로컬/샘플 실행을 위한 Dockerfile, compose 예시
- `helm/`
  - Helm values 예시
- `themes/`
  - 커스텀 로그인 테마 리소스

## 상태 안내

현재 저장소의 실제 SPI 소스 경로는 `spi-modules/`이며,
`docker/` 하위 일부 파일은 과거 경로(`spi/`, `terms-ra` 등)를 가정한 예시가 포함되어 있다.

따라서 운영 적용 전에는 반드시 아래를 점검해야 한다.

1. Docker 빌드 컨텍스트의 SPI 경로
2. 빌드 모듈 이름(`terms-action`, `claim-mappers`, `userinfo-sync`, `access-approval-action`)
3. Keycloak 이미지 버전(운영 표준과 일치 여부)
4. compose 환경변수 오타/보안 값

이 디렉터리는 "즉시 배포용 단일 진실 소스"라기보다 배포 템플릿/참고 자료로 사용한다.
