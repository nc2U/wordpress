# wp-config.php NFS 설정 가이드

## 🚨 문제 상황

**에러**: `failed to create subPath directory for volumeMount "wordpress-nfs"`

**원인**: NFS에 `wp-config.php` 파일이 없어서 Kubernetes가 subPath를 생성할 수 없음

## 🔧 해결 방법

### 1단계: Pod 시작하기 (wp-config.php 마운트 비활성화)

현재 `wordpress-deployment.yaml`에서 wp-config.php 마운트가 주석 처리되어 있습니다.

```bash
# Helm 차트 업그레이드
helm upgrade wp . -n wp

# Pod 상태 확인
kubectl get pods -n wp -w
# wp-wordpress Pod가 Running 상태가 될 때까지 대기
```

### 2단계: wp-config.php를 NFS에 복사

#### 방법 1: Pod에서 직접 복사 (권장)

```bash
# 1. WordPress Pod 이름 확인
kubectl get pods -n wp -l app=wordpress

# 2. wp-config.php 내용 확인
kubectl exec -n wp deploy/wp-wordpress -- cat /var/www/html/wp-config.php

# 3. 로컬에 복사
kubectl exec -n wp deploy/wp-wordpress -- cat /var/www/html/wp-config.php > /tmp/wp-config.php

# 4. 임시 Pod 생성하여 NFS에 복사
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nfs-copy
  namespace: wp
spec:
  containers:
  - name: copy
    image: busybox
    command: ["sleep", "300"]
    volumeMounts:
    - name: nfs
      mountPath: /mnt/nfs
  volumes:
  - name: nfs
    nfs:
      server: dyibs.synology.me
      path: /volume1/mnt/wordpress
EOF

# 5. Pod가 Ready 될 때까지 대기
kubectl wait --for=condition=Ready pod/nfs-copy -n wp --timeout=60s

# 6. wp-config.php를 NFS로 복사
kubectl cp /tmp/wp-config.php wp/nfs-copy:/mnt/nfs/wp-config.php

# 7. 권한 설정
kubectl exec -n wp nfs-copy -- chmod 644 /mnt/nfs/wp-config.php

# 8. 파일 확인
kubectl exec -n wp nfs-copy -- ls -la /mnt/nfs/wp-config.php

# 9. 임시 Pod 삭제
kubectl delete pod -n wp nfs-copy
```

#### 방법 2: Synology NAS에 직접 접속

Synology에 SSH 또는 파일 관리자로 접속:

```bash
# SSH로 Synology 접속
ssh admin@dyibs.synology.me

# wp-config.php 생성
cd /volume1/mnt/wordpress/
vi wp-config.php
# (내용 붙여넣기)

# 권한 설정
chown 33:33 wp-config.php  # www-data
chmod 644 wp-config.php
```

### 3단계: NFS 디렉토리 구조 확인

```bash
# 임시 Pod로 확인
kubectl run nfs-check --image=busybox --restart=Never -n wp \
  --overrides='{"spec":{"volumes":[{"name":"nfs","nfs":{"server":"dyibs.synology.me","path":"/volume1/mnt/wordpress"}}],"containers":[{"name":"check","image":"busybox","command":["ls","-la","/mnt/nfs"],"volumeMounts":[{"name":"nfs","mountPath":"/mnt/nfs"}]}]}}'

# 로그 확인
kubectl logs -n wp nfs-check

# 예상 출력:
# -rw-r--r-- 1 33 33 3456 Nov 2 12:00 wp-config.php
# drwxr-xr-x 5 33 33  160 Nov 2 12:00 wp-content

# Pod 삭제
kubectl delete pod -n wp nfs-check
```

최종 NFS 디렉토리 구조:
```
/volume1/mnt/wordpress/
├── wp-config.php      ← 파일이어야 함 (디렉토리 아님!)
└── wp-content/
    ├── plugins/
    ├── themes/
    └── uploads/
```

### 4단계: wp-config.php 마운트 활성화

`templates/wordpress-deployment.yaml` 수정:

```yaml
volumeMounts:
  - name: wordpress-data
    mountPath: /var/www/html
  - name: wordpress-nfs
    mountPath: /var/www/html/wp-content
    subPath: wp-content
  - name: wordpress-nfs              # 주석 제거
    mountPath: /var/www/html/wp-config.php
    subPath: wp-config.php
```

### 5단계: Helm 차트 재배포

```bash
# Helm 차트 업그레이드
helm upgrade wp . -n wp

# Pod 재시작 확인
kubectl get pods -n wp -w

# Pod가 Running 상태가 되면 Ctrl+C
```

### 6단계: 확인

```bash
# 1. Pod 내부에서 wp-config.php 확인
kubectl exec -n wp deploy/wp-wordpress -- ls -la /var/www/html/wp-config.php
# 출력: -rw-r--r-- 1 www-data www-data ... wp-config.php

# 2. 파일 내용 확인
kubectl exec -n wp deploy/wp-wordpress -- head -20 /var/www/html/wp-config.php

# 3. 마운트 확인
kubectl exec -n wp deploy/wp-wordpress -- mount | grep wp-config
# 출력: dyibs.synology.me:/volume1/mnt/wordpress/wp-config.php on /var/www/html/wp-config.php type nfs4 ...

# 4. WordPress 접속 테스트
curl -I https://dyibs.com
# HTTP/1.1 200 OK 또는 301/302 (정상)
```

## 🔍 트러블슈팅

### Pod가 여전히 시작되지 않음

**증상**: `failed to create subPath directory`

**해결**:
```bash
# 1. NFS에 wp-config.php가 파일인지 확인
kubectl run nfs-test --image=busybox --rm -it --restart=Never -n wp \
  --overrides='{"spec":{"volumes":[{"name":"nfs","nfs":{"server":"dyibs.synology.me","path":"/volume1/mnt/wordpress"}}],"containers":[{"name":"test","image":"busybox","command":["sh","-c","ls -la /mnt/nfs/wp-config.php && cat /mnt/nfs/wp-config.php | head -5"],"volumeMounts":[{"name":"nfs","mountPath":"/mnt/nfs"}]}]}}'

# 2. 파일이 디렉토리로 되어 있으면 삭제
kubectl run nfs-fix --image=busybox --rm -it --restart=Never -n wp \
  --overrides='{"spec":{"volumes":[{"name":"nfs","nfs":{"server":"dyibs.synology.me","path":"/volume1/mnt/wordpress"}}],"containers":[{"name":"fix","image":"busybox","command":["sh","-c","rm -rf /mnt/nfs/wp-config.php"],"volumeMounts":[{"name":"nfs","mountPath":"/mnt/nfs"}]}]}}'

# 3. 올바른 파일로 다시 복사 (위의 방법 1 재실행)
```

### wp-config.php가 읽기 전용

**증상**: WordPress에서 설정 저장 안 됨

**해결**:
```bash
# 권한 확인 및 수정
kubectl run nfs-chmod --image=busybox --rm -it --restart=Never -n wp \
  --overrides='{"spec":{"volumes":[{"name":"nfs","nfs":{"server":"dyibs.synology.me","path":"/volume1/mnt/wordpress"}}],"containers":[{"name":"chmod","image":"busybox","command":["chmod","644","/mnt/nfs/wp-config.php"],"volumeMounts":[{"name":"nfs","mountPath":"/mnt/nfs"}]}]}}'
```

### WordPress 설치 화면이 나옴

**증상**: wp-config.php는 마운트되었지만 WordPress가 설치 화면을 표시

**원인**: wp-config.php 내용이 잘못되었거나 데이터베이스 연결 실패

**해결**:
```bash
# 1. wp-config.php 내용 확인
kubectl exec -n wp deploy/wp-wordpress -- cat /var/www/html/wp-config.php | grep DB_

# 2. 데이터베이스 연결 테스트
kubectl exec -n wp deploy/wp-wordpress -- \
  mysql -h wp-mariadb -u wordpress -p wordpress -e "SELECT 1"
# 비밀번호 입력 필요

# 3. wp-config.php가 올바른지 확인
# DB_NAME, DB_USER, DB_PASSWORD, DB_HOST가 올바른지 확인
```

## 📝 체크리스트

설정 완료 후 확인:

- [ ] NFS에 wp-config.php 파일 존재 (디렉토리 아님)
- [ ] 파일 권한: 644 (rw-r--r--)
- [ ] 파일 소유자: 33:33 (www-data)
- [ ] Pod가 Running 상태
- [ ] Pod 내부에서 /var/www/html/wp-config.php 파일 존재
- [ ] 마운트 타입이 nfs4
- [ ] WordPress 사이트 정상 접속
- [ ] wp-admin 로그인 가능

## 🎉 완료!

이제 wp-config.php도 NFS에 안전하게 보관되어, Pod를 재시작하거나 업데이트해도 설정이 유지됩니다.

## 💡 참고: wp-config.php 사용하지 않기

wp-config.php를 NFS에 보관하지 않고 local-path에만 두려면:

```yaml
# values.yaml
wordpress:
  nfs:
    preservePaths:
      wpContent: true
      wpConfig: false    # wp-config.php는 NFS 사용 안 함
```

이 경우 wp-config.php는 각 Pod의 local-path PVC에 저장됩니다.