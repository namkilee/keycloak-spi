# Bootstrap (Keycloak Terraform)

`infra/bootstrap`은 Keycloak 초기 부트스트랩을 담당한다.

## 생성 대상

- bootstrap realm
- Terraform service-account client(환경 루트에서 재사용)
- 환경 루트(`infra/dev|stg|prd`)가 참조할 output 값

## 실행

```bash
cd keycloak-config/infra/bootstrap
terraform init
terraform apply -var-file=terraform.tfvars
```

## 주의사항

- `terraform.tfvars`는 커밋 금지 (민감정보 포함 가능)
- bootstrap state에는 client secret이 포함될 수 있으므로 백엔드 접근권한을 최소화
- `infra/dev|stg|prd`는 bootstrap remote state에 의존하므로 bootstrap을 먼저 적용해야 함
