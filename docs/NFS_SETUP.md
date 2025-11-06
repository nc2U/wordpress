# NFS Storage Setup for WordPress

이 가이드는 WordPress의 wp-content와 wp-config.php를 NFS 스토리지에 보존하는 방법을 설명합니다.

## 📋 개요

이 Helm 차트는 다음과 같은 스토리지 구성을 사용합니다:

```
┌─────────────────────────────────────────┐
│      WordPress Pod                      │
├─────────────────────────────────────────┤
│                                         │
│  /var/www/html/                        │
│  ├── (local-path PVC) ←─ 기본 파일들  │
│  ├── wp-content/ (NFS) ←─ 플러그인,    │
│  │                         테마, 미디어 │
│  └── wp-config.php (NFS) ←─ 설정 파일  │
│                                         │
└─────────────────────────────────────────┘
```

### 스토리지 구성

| 경로 | 스토리지 타입 | 용도 |
|------|--------------|------|
| `/var/www/html/` | local-path PVC | WordPress 기본 파일 (코어) |
| `/var/www/html/wp-content/` | NFS | 플러그인, 테마, 업로드 파일 |
| `/var/www/html/wp-config.php` | NFS | WordPress 설정 파일 |

## 🎯 왜 NFS를 사용하나요?

### wp-content를 NFS에 보관하는 이유
- ✅ **데이터 공유**: 여러 WordPress replica가 동일한 플러그인/테마 사용
- ✅ **백업 용이**: NFS 서버에서 중앙 집중식 백업
- ✅ **미디어 관리**: 업로드된 이미지/파일을 모든 Pod에서 접근
- ✅ **스케일링**: ReadWriteMany로 수평 확장 지원

### wp-config.php를 NFS에 보관하는 이유
- ✅ **설정 보존**: Pod 재시작/업데이트 시에도 설정 유지
- ✅ **일관성**: 모든 replica가 동일한 설정 사용
- ✅ **백업**: 중요한 설정 파일 안전하게 보관

## 🚀 초기 설정

### 1. NFS 서버 준비

#### Synology NAS 예시

```bash
# 1. Synology에 공유 폴더 생성
# Control Panel → Shared Folder → Create
# 이름: wordpress
# 경로: /volume1/mnt/wordpress

# 2. NFS 권한 설정
# Control Panel → Shared Folder → Edit → NFS Permissions
# 호스트: * (또는 Kubernetes 노드 IP 범위)
# 권한: Read/Write
# Squash: Map all users to admin
# 보안: sys
```

#### Linux NFS 서버 예시

```bash
# NFS 서버에서
sudo mkdir -p /exports/wordpress
sudo chown nobody:nogroup /exports/wordpress
sudo chmod 777 /exports/wordpress

# /etc/exports 편집
echo "/exports/wordpress *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports

# NFS 서버 재시작
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

### 2. NFS에 초기 파일 배치

#### 방법 1: 기존 WordPress에서 복사

```bash
# 기존 WordPress Pod에서 wp-content 복사
kubectl cp wp/your-wordpress-pod:/var/www/html/wp-content /tmp/wp-content

# NFS 마운트 후 복사
sudo mount -t nfs dyibs.synology.me:/volume1/mnt/wordpress /mnt/nfs
sudo cp -r /tmp/wp-content /mnt/nfs/
sudo umount /mnt/nfs
```

#### 방법 2: 임시 Pod로 직접 복사

```bash
# 임시 Pod 생성하여 NFS 마운트
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nfs-setup
  namespace: wp
spec:
  containers:
  - name: setup
    image: ubuntu:22.04
    command: ["sleep", "3600"]
    volumeMounts:
    - name: nfs
      mountPath: /mnt/nfs
  volumes:
  - name: nfs
    nfs:
      server: dyibs.synology.me
      path: /volume1/mnt/wordpress
EOF

# Pod에 접속하여 디렉토리 생성
kubectl exec -it -n wp nfs-setup -- bash
mkdir -p /mnt/nfs/wp-content
exit

# 기존 WordPress에서 파일 복사
kubectl exec -n wp deploy/your-wordpress -- tar czf /tmp/wp-content.tar.gz -C /var/www/html wp-content
kubectl cp wp/your-wordpress-pod:/tmp/wp-content.tar.gz /tmp/wp-content.tar.gz

# NFS로 복사
kubectl cp /tmp/wp-content.tar.gz wp/nfs-setup:/mnt/nfs/
kubectl exec -n wp nfs-setup -- tar xzf /mnt/nfs/wp-content.tar.gz -C /mnt/nfs/

# 정리
kubectl delete pod -n wp nfs-setup
```

### 3. wp-config.php 준비

#### 신규 설치인 경우

1. WordPress를 먼저 설치하여 wp-config.php 생성
2. 생성된 wp-config.php를 NFS로 복사

```bash
# WordPress Pod에서 wp-config.php 가져오기
kubectl cp wp/your-wordpress-pod:/var/www/html/wp-config.php /tmp/wp-config.php

# NFS에 복사
# 방법 1: 직접 마운트
sudo mount -t nfs dyibs.synology.me:/volume1/mnt/wordpress /mnt/nfs
sudo cp /tmp/wp-config.php /mnt/nfs/
sudo umount /mnt/nfs

# 방법 2: 임시 Pod 사용
kubectl run nfs-copy --image=ubuntu:22.04 --restart=Never -n wp \
  --overrides='{"spec":{"volumes":[{"name":"nfs","nfs":{"server":"dyibs.synology.me","path":"/volume1/mnt/wordpress"}}],"containers":[{"name":"nfs-copy","image":"ubuntu:22.04","command":["sleep","300"],"volumeMounts":[{"name":"nfs","mountPath":"/mnt/nfs"}]}]}}'

kubectl cp /tmp/wp-config.php wp/nfs-copy:/mnt/nfs/wp-config.php
kubectl delete pod -n wp nfs-copy
```

#### 기존 설치인 경우

```bash
# 기존 WordPress에서 wp-config.php 복사
kubectl exec -n wp deploy/your-wordpress -- cat /var/www/html/wp-config.php > /tmp/wp-config.php

# NFS에 배치 (위와 동일)
```

### 4. NFS 디렉토리 구조 확인

최종적으로 NFS 서버의 `/volume1/mnt/wordpress/` 디렉토리는 다음과 같아야 합니다:

```
/volume1/mnt/wordpress/
├── wp-content/
│   ├── plugins/
│   ├── themes/
│   ├── uploads/
│   └── ...
└── wp-config.php
```

## 🔧 values.yaml 설정

### 기본 설정

```yaml
wordpress:
  nfs:
    enabled: true
    server: "dyibs.synology.me"
    path: "/volume1/mnt/wordpress"
    size: "2Gi"
    mountOptions:
      - nfsvers=4.1
      - rsize=1048576
      - wsize=1048576
      - hard
      - timeo=600
      - retrans=2
    preservePaths:
      wpContent: true      # wp-content 마운트
      wpConfig: true       # wp-config.php 마운트
```

### 설정 옵션 설명

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `nfs.enabled` | NFS 사용 여부 | `true` |
| `nfs.server` | NFS 서버 주소 | `dyibs.synology.me` |
| `nfs.path` | NFS 서버 경로 | `/volume1/mnt/wordpress` |
| `nfs.size` | PV 크기 | `2Gi` |
| `nfs.mountOptions` | NFS 마운트 옵션 | 위 참조 |
| `preservePaths.wpContent` | wp-content 마운트 | `true` |
| `preservePaths.wpConfig` | wp-config.php 마운트 | `true` |

## 📊 배포 및 확인

### 1. Helm 차트 배포

```bash
# 새로 설치
helm install wp . -n wp

# 업그레이드
helm upgrade wp . -n wp
```

### 2. 마운트 확인

```bash
# Pod에 접속
kubectl exec -it -n wp deploy/wp-wordpress -- bash

# 마운트 확인
df -h | grep nfs
# 출력 예시:
# dyibs.synology.me:/volume1/mnt/wordpress  2.0G  500M  1.5G  25% /var/www/html/wp-content

# wp-content 확인
ls -la /var/www/html/wp-content/
# 플러그인, 테마, 업로드 파일 보여야 함

# wp-config.php 확인
ls -la /var/www/html/wp-config.php
cat /var/www/html/wp-config.php
```

### 3. 파일 권한 확인

```bash
# WordPress Pod 내부에서
ls -la /var/www/html/wp-config.php
# -rw-r--r-- 1 www-data www-data ... wp-config.php

ls -la /var/www/html/wp-content/
# drwxr-xr-x ... www-data www-data ... plugins
# drwxr-xr-x ... www-data www-data ... themes
# drwxr-xr-x ... www-data www-data ... uploads
```

## 🔧 트러블슈팅

### Pod가 시작되지 않음 (CrashLoopBackOff)

**원인**: wp-config.php가 NFS에 없음

**해결**:
```bash
# 1. Pod 로그 확인
kubectl logs -n wp deploy/wp-wordpress

# 2. wp-config.php 존재 확인
kubectl exec -n wp nfs-setup -- ls -la /mnt/nfs/wp-config.php

# 3. 파일이 없으면 생성
# preservePaths.wpConfig를 false로 설정하여 임시로 배포
helm upgrade wp . -n wp --set wordpress.nfs.preservePaths.wpConfig=false

# 4. WordPress 설치 완료 후 wp-config.php 복사
kubectl exec -n wp deploy/wp-wordpress -- cat /var/www/html/wp-config.php > /tmp/wp-config.php
# NFS에 복사 (위의 방법 참조)

# 5. 다시 wpConfig=true로 설정하고 재배포
helm upgrade wp . -n wp --set wordpress.nfs.preservePaths.wpConfig=true
```

### wp-config.php가 디렉토리로 마운트됨

**원인**: NFS에 wp-config.php 파일이 없어서 디렉토리로 생성됨

**해결**:
```bash
# 1. Pod 삭제
kubectl delete pod -n wp -l app=wordpress

# 2. NFS에서 잘못된 디렉토리 삭제
# NFS 서버 또는 임시 Pod에서
rm -rf /volume1/mnt/wordpress/wp-config.php

# 3. 올바른 파일 배치
# wp-config.php 파일을 NFS에 복사 (위의 방법 참조)

# 4. Pod 재시작
kubectl rollout restart deployment -n wp wp-wordpress
```

### NFS 마운트 실패

**원인**: NFS 서버 연결 문제 또는 권한 문제

**해결**:
```bash
# 1. NFS 서버 연결 테스트
kubectl run -it --rm nfs-test --image=ubuntu:22.04 --restart=Never -- bash
apt-get update && apt-get install -y nfs-common
mount -t nfs dyibs.synology.me:/volume1/mnt/wordpress /mnt
ls -la /mnt
umount /mnt
exit

# 2. Kubernetes 노드에서 NFS 테스트
# (노드에 SSH 접속)
sudo mount -t nfs dyibs.synology.me:/volume1/mnt/wordpress /mnt
ls -la /mnt
sudo umount /mnt

# 3. NFS 서버 권한 확인
# Synology: Control Panel → Shared Folder → NFS Permissions
# Linux: /etc/exports 확인
```

### 파일 권한 오류

**원인**: NFS 파일 소유권이 www-data가 아님

**해결**:
```bash
# NFS 서버에서 (또는 임시 Pod에서)
# www-data UID는 보통 33
chown -R 33:33 /volume1/mnt/wordpress/wp-content
chown 33:33 /volume1/mnt/wordpress/wp-config.php
chmod 644 /volume1/mnt/wordpress/wp-config.php
chmod -R 755 /volume1/mnt/wordpress/wp-content
```

## 💾 백업

### wp-content 백업

```bash
# NFS 서버에서 직접
tar czf /backup/wp-content-$(date +%Y%m%d).tar.gz \
  -C /volume1/mnt/wordpress wp-content

# 또는 Kubernetes에서
kubectl run backup --image=ubuntu:22.04 --restart=Never -n wp \
  --overrides='{"spec":{"volumes":[{"name":"nfs","nfs":{"server":"dyibs.synology.me","path":"/volume1/mnt/wordpress"}}],"containers":[{"name":"backup","image":"ubuntu:22.04","command":["tar","czf","/backup/wp-content.tar.gz","-C","/mnt/nfs","wp-content"],"volumeMounts":[{"name":"nfs","mountPath":"/mnt/nfs"}]}]}}'

kubectl cp wp/backup:/backup/wp-content.tar.gz ./wp-content-backup.tar.gz
kubectl delete pod -n wp backup
```

### wp-config.php 백업

```bash
# NFS 서버에서
cp /volume1/mnt/wordpress/wp-config.php \
  /backup/wp-config-$(date +%Y%m%d).php

# Kubernetes에서
kubectl exec -n wp deploy/wp-wordpress -- \
  cat /var/www/html/wp-config.php > wp-config-backup.php
```

## 🔄 wp-content만 사용하고 wp-config.php는 local-path 사용

wp-config.php를 NFS에 저장하지 않으려면:

```yaml
wordpress:
  nfs:
    enabled: true
    preservePaths:
      wpContent: true
      wpConfig: false    # wp-config.php는 local-path에 저장
```

이 경우 wp-config.php는 각 Pod의 local-path PVC에 저장되므로, ConfigMap이나 Secret으로 관리하는 것을 권장합니다.

## 📚 추가 리소스

- [Kubernetes NFS Documentation](https://kubernetes.io/docs/concepts/storage/volumes/#nfs)
- [WordPress File Permissions](https://wordpress.org/support/article/changing-file-permissions/)
- [Synology NFS Setup Guide](https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/file_share_nfs)

## 🎉 완료!

이제 wp-content와 wp-config.php가 NFS에 안전하게 보관되며, Pod를 재시작하거나 업데이트해도 데이터가 유지됩니다.