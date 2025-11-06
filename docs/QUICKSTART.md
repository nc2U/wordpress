# WordPress Helm Chart - Quick Start Guide

공식 WordPress + Apache 기반 Helm 차트를 빠르게 설치하고 운영하는 가이드입니다.

## 🎯 사전 요구사항

- Kubernetes 클러스터 (1.19+)
- Helm 3.0+
- Nginx Ingress Controller
- cert-manager (SSL/TLS 자동화 시)
- StorageClass (PVC 자동 프로비저닝)

## 📋 빠른 설치 (5분)

### 1. 네임스페이스 생성

```bash
kubectl create namespace wp
```

### 2. values.yaml 설정

비밀번호 설정 (필수):

```yaml
wordpress:
  wordpressUsername: admin
  wordpressPassword: "your-secure-password"
  wordpressEmail: admin@example.com

mariadb:
  auth:
    rootPassword: "your-root-password"
    password: "your-db-password"
```

### 3. Helm 차트 설치

```bash
# Dry-run으로 먼저 확인
helm install wp . -n wp --dry-run --debug

# 실제 설치
helm install wp . -n wp

# 설치 확인
kubectl get pods -n wp -w
```

### 4. 접속 확인

```bash
# Ingress 확인
kubectl get ingress -n wp

# 웹사이트 접속
open https://your-domain.com
open https://your-domain.com/wp-admin
```

## 🚀 상세 설치 가이드

### Step 1: 설정 파일 준비

`values.yaml`에서 다음 항목을 수정하세요:

```yaml
wordpress:
  # WordPress 관리자 정보
  wordpressUsername: admin
  wordpressPassword: "your-secure-password"
  wordpressEmail: admin@example.com
  wordpressBlogName: "My WordPress Site"

  # Ingress 설정
  ingress:
    enabled: true
    className: "nginx"
    hosts:
      - host: your-domain.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: your-domain-tls
        hosts:
          - your-domain.com

mariadb:
  auth:
    database: wordpress
    username: wordpress
    password: "your-db-password"
    rootPassword: "your-root-password"
```

### Step 2: 시크릿을 통한 비밀번호 관리 (권장)

```bash
# MariaDB 비밀번호 시크릿 생성
kubectl create secret generic wp-db-secret \
  --from-literal=mariadb-password='your-db-password' \
  --from-literal=mariadb-root-password='your-root-password' \
  -n wp

# values.yaml에서 existingSecret 설정
# mariadb:
#   auth:
#     existingSecret: "wp-db-secret"
```

### Step 3: cert-manager 설정 (선택사항)

Let's Encrypt 자동 SSL/TLS:

```bash
# ClusterIssuer 생성
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### Step 4: Helm 차트 설치

```bash
# 설치
helm install wp . -n wp

# 상태 확인
helm status wp -n wp

# 모든 리소스 확인
kubectl get all,pvc,secret,ingress -n wp
```

## ✅ 검증 체크리스트

설치가 완료되면 다음을 확인하세요:

- [ ] 모든 Pod가 Running 상태입니다
- [ ] WordPress 사이트가 정상적으로 열립니다
- [ ] HTTPS (SSL/TLS)가 작동합니다 (cert-manager 사용 시)
- [ ] 관리자 페이지 로그인이 됩니다
- [ ] 게시물 작성이 가능합니다
- [ ] 미디어 업로드가 작동합니다

## 🔧 트러블슈팅

### Pod가 시작되지 않습니다

```bash
# Pod 상태 확인
kubectl get pods -n wp
kubectl describe pod -n wp <pod-name>

# 로그 확인
kubectl logs -n wp <pod-name>
```

### 데이터베이스 연결 오류

```bash
# MariaDB 연결 테스트
kubectl exec -n wp deploy/wp-wordpress -- \
  mysql -h wp-mariadb -u wordpress -p wordpress -e "SELECT 1"

# Secret 확인
kubectl get secret -n wp wp-mariadb -o yaml
```

### Ingress가 작동하지 않습니다

```bash
# Ingress 상세 확인
kubectl describe ingress -n wp

# Nginx Ingress 로그
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

### PVC가 바인딩되지 않습니다

```bash
# PVC 상태 확인
kubectl get pvc -n wp

# StorageClass 확인
kubectl get storageclass

# 이벤트 확인
kubectl get events -n wp --sort-by='.lastTimestamp'
```

## 📊 모니터링

### 리소스 사용량 확인

```bash
# Pod 리소스 사용량
kubectl top pods -n wp

# 스토리지 사용량
kubectl exec -n wp deploy/wp-wordpress -- df -h /var/www/html
```

### 로그 모니터링

```bash
# WordPress 로그
kubectl logs -n wp -l app=wordpress -f

# MariaDB 로그
kubectl logs -n wp -l app=mariadb -f
```

## 🔄 업그레이드

### WordPress 버전 업그레이드

```bash
# values.yaml 수정
# wordpress:
#   image:
#     tag: "6.5.0-apache"

# 업그레이드 실행
helm upgrade wp . -n wp

# 상태 확인
kubectl rollout status deployment/wp-wordpress -n wp
```

### 설정 변경

```bash
# Replica 수 증가
helm upgrade wp . -n wp --set wordpress.replicaCount=3

# 리소스 제한 변경
helm upgrade wp . -n wp \
  --set wordpress.resources.limits.memory=2Gi \
  --set wordpress.resources.limits.cpu=2000m
```

## 💾 백업

### 데이터베이스 백업

```bash
# 데이터베이스 덤프
kubectl exec -n wp statefulset/wp-mariadb-0 -- \
  mysqldump -u root -p<root-password> wordpress \
  > wordpress-backup-$(date +%Y%m%d).sql
```

### 파일 백업

```bash
# WordPress 파일 백업
POD=$(kubectl get pod -n wp -l app=wordpress -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n wp $POD -- tar czf /tmp/wp-files.tar.gz -C /var/www/html .
kubectl cp wp/$POD:/tmp/wp-files.tar.gz ./wordpress-files-$(date +%Y%m%d).tar.gz
```

## 🧹 삭제

```bash
# Helm 릴리스 삭제 (PVC는 유지됨)
helm uninstall wp -n wp

# PVC도 함께 삭제 (주의!)
kubectl delete pvc -n wp --all

# 네임스페이스 삭제
kubectl delete namespace wp
```

## 📚 추가 문서

- **전체 문서**: [README.md](../README.md)
- **설정 옵션**: [values.yaml](../values.yaml)
- **프로젝트 요약**: [SUMMARY.md](SUMMARY.md)

## 💡 유용한 명령어

```bash
# Helm 릴리스 목록
helm list -n wp

# Helm 릴리스 히스토리
helm history wp -n wp

# 현재 values 확인
helm get values wp -n wp

# 전체 매니페스트 확인
helm get manifest wp -n wp

# 템플릿 렌더링 테스트
helm template wp . -n wp
```

## 🎉 완료!

WordPress가 성공적으로 설치되었습니다!

**다음 단계**:
1. 테마 설치 및 커스터마이징
2. 필요한 플러그인 설치
3. 정기 백업 스케줄 설정
4. 모니터링 설정 (Prometheus + Grafana)
5. CDN 연동 고려

문제가 있으면 [README.md](../README.md)의 트러블슈팅 섹션을 참조하세요.