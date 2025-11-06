# WordPress 파일 보존 가이드

## 📁 WordPress 디렉토리 구조

```
/var/www/html/
├── wp-admin/              ❌ 코어 (보존 불필요)
├── wp-includes/           ❌ 코어 (보존 불필요)
├── wp-content/            ✅ 보존 필요 (NFS)
│   ├── plugins/
│   ├── themes/
│   ├── uploads/
│   ├── languages/
│   ├── mu-plugins/
│   └── upgrade/
├── wp-config.php          ✅ 보존 필요 (NFS)
├── .htaccess              ⚠️ 보존 권장
├── robots.txt             ⚠️ 보존 권장
├── sitemap.xml            ⚠️ 보존 권장 (수동 생성 시)
├── favicon.ico            ⚠️ 보존 가능
├── index.php              ❌ 코어 (보존 불필요)
├── wp-*.php               ❌ 코어 (보존 불필요)
└── ...
```

## ✅ 현재 보존 중인 파일

### 1. wp-content/ (NFS)
- **plugins/**: 설치된 모든 플러그인
- **themes/**: 설치된 모든 테마
- **uploads/**: 업로드된 미디어 파일 (이미지, 동영상, PDF 등)
- **languages/**: 언어 팩
- **mu-plugins/**: Must-Use 플러그인 (있는 경우)

### 2. wp-config.php (NFS)
- 데이터베이스 연결 정보
- 보안 키 (AUTH_KEY, SECURE_AUTH_KEY 등)
- 디버그 설정
- 기타 WordPress 설정

## ⚠️ 추가 보존 권장 파일

### 1. .htaccess ⭐ 매우 중요

**보존 필요 이유**:
- WordPress 퍼머링크 규칙
- 리다이렉트 설정 (www → non-www, HTTP → HTTPS)
- 보안 규칙 (wp-admin 접근 제한 등)
- 성능 최적화 (브라우저 캐싱, Gzip 압축)
- 플러그인이 추가한 규칙

**기본 .htaccess vs 커스터마이징**:

기본 WordPress .htaccess:
```apache
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
```

커스터마이징 예시 (보존 필요):
```apache
# BEGIN WordPress
...
# END WordPress

# 보안 규칙
<Files wp-config.php>
order allow,deny
deny from all
</Files>

# HTTPS 리다이렉트
RewriteCond %{HTTPS} off
RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

# 브라우저 캐싱
<IfModule mod_expires.c>
ExpiresActive On
ExpiresByType image/jpg "access plus 1 year"
ExpiresByType image/jpeg "access plus 1 year"
ExpiresByType image/gif "access plus 1 year"
ExpiresByType image/png "access plus 1 year"
</IfModule>
```

**확인 방법**:
```bash
# 현재 .htaccess 확인
kubectl exec -n wp deploy/wp-wordpress -- cat /var/www/html/.htaccess
```

### 2. robots.txt ⭐ SEO 중요

**보존 필요 이유**:
- 검색 엔진 크롤링 규칙
- SEO 최적화 설정
- 특정 경로 차단/허용

**기본 vs 커스터마이징**:

WordPress 기본 (가상, 물리 파일 없음):
```
User-agent: *
Disallow: /wp-admin/
Allow: /wp-admin/admin-ajax.php
```

커스터마이징 예시 (보존 필요):
```
User-agent: *
Disallow: /wp-admin/
Disallow: /wp-includes/
Disallow: /wp-content/plugins/
Disallow: /wp-content/themes/
Allow: /wp-admin/admin-ajax.php
Allow: /wp-content/uploads/

Sitemap: https://dyibs.com/sitemap.xml
```

**확인 방법**:
```bash
# robots.txt 존재 확인
kubectl exec -n wp deploy/wp-wordpress -- ls -la /var/www/html/robots.txt

# 내용 확인
kubectl exec -n wp deploy/wp-wordpress -- cat /var/www/html/robots.txt
```

### 3. 기타 루트 레벨 파일

**favicon.ico, apple-touch-icon.png**:
- 브랜드 아이콘
- 보존 권장 (재생성 가능하지만 번거로움)

**sitemap.xml** (수동 생성 시):
- SEO 사이트맵
- 플러그인(Yoast SEO, RankMath 등)이 자동 생성하면 불필요
- 수동 생성한 경우 보존 필요

**기타 커스텀 파일**:
- ads.txt (광고 관련)
- crossdomain.xml (Flash 관련, 구식)
- 기타 사용자가 추가한 파일

## 🔧 .htaccess와 robots.txt 보존 방법

### 방법 1: NFS에 추가 (권장)

#### 1.1 NFS에 파일 배치

```bash
# 현재 파일 가져오기
kubectl exec -n wp deploy/wp-wordpress -- cat /var/www/html/.htaccess > /tmp/.htaccess
kubectl exec -n wp deploy/wp-wordpress -- cat /var/www/html/robots.txt > /tmp/robots.txt

# NFS에 복사
sudo mount -t nfs dyibs.synology.me:/volume1/mnt/wordpress /mnt/nfs
sudo cp /tmp/.htaccess /mnt/nfs/
sudo cp /tmp/robots.txt /mnt/nfs/
sudo chown 33:33 /mnt/nfs/.htaccess /mnt/nfs/robots.txt
sudo chmod 644 /mnt/nfs/.htaccess /mnt/nfs/robots.txt
sudo umount /mnt/nfs
```

#### 1.2 wordpress-deployment.yaml 수정

```yaml
volumeMounts:
  - name: wordpress-data
    mountPath: /var/www/html
  - name: wordpress-nfs
    mountPath: /var/www/html/wp-content
    subPath: wp-content
  - name: wordpress-nfs
    mountPath: /var/www/html/wp-config.php
    subPath: wp-config.php
  - name: wordpress-nfs
    mountPath: /var/www/html/.htaccess
    subPath: .htaccess
  - name: wordpress-nfs
    mountPath: /var/www/html/robots.txt
    subPath: robots.txt
```

#### 1.3 values.yaml 업데이트

```yaml
wordpress:
  nfs:
    preservePaths:
      wpContent: true
      wpConfig: true
      htaccess: true      # 추가
      robotsTxt: true     # 추가
```

### 방법 2: ConfigMap 사용 (간단한 파일용)

```bash
# .htaccess를 ConfigMap으로 생성
kubectl create configmap wp-htaccess \
  --from-file=.htaccess=/tmp/.htaccess \
  -n wp

# robots.txt를 ConfigMap으로 생성
kubectl create configmap wp-robots \
  --from-file=robots.txt=/tmp/robots.txt \
  -n wp
```

deployment에 마운트:
```yaml
volumeMounts:
  - name: htaccess
    mountPath: /var/www/html/.htaccess
    subPath: .htaccess
  - name: robots
    mountPath: /var/www/html/robots.txt
    subPath: robots.txt

volumes:
  - name: htaccess
    configMap:
      name: wp-htaccess
  - name: robots
    configMap:
      name: wp-robots
```

### 방법 3: 보존하지 않고 관리

WordPress와 플러그인이 자동 생성하도록 두고:
- .htaccess: WordPress가 퍼머링크 설정 시 자동 생성
- robots.txt: Yoast SEO/RankMath 같은 플러그인이 관리

**장점**: 간단함
**단점**: 커스터마이징 손실 가능

## 🚨 보존하지 말아야 할 파일

### WordPress 코어 파일 (자동 관리)
- wp-admin/
- wp-includes/
- index.php
- wp-*.php
- license.txt, readme.html

**이유**: WordPress 업데이트 시 자동으로 교체되어야 함

### 임시 파일
- wp-content/upgrade/
- wp-content/cache/ (캐싱 플러그인)
- .maintenance

## 📊 권장 보존 전략

### 최소 보존 (현재 구성) ✅
```
NFS:
├── wp-content/
└── wp-config.php
```

### 권장 보존 (추가 권장) ⭐
```
NFS:
├── wp-content/
├── wp-config.php
├── .htaccess
└── robots.txt
```

### 완전 보존 (최대 안전성)
```
NFS:
├── wp-content/
├── wp-config.php
├── .htaccess
├── robots.txt
├── favicon.ico
├── apple-touch-icon.png
└── sitemap.xml (수동 생성 시)
```

## 🔍 현재 파일 확인 체크리스트

```bash
# 1. .htaccess 확인
kubectl exec -n wp deploy/wp-wordpress -- cat /var/www/html/.htaccess
# → 기본 WordPress 규칙만 있는지, 커스텀 규칙이 있는지 확인

# 2. robots.txt 확인
kubectl exec -n wp deploy/wp-wordpress -- cat /var/www/html/robots.txt
# → 파일이 있는지, 커스텀 규칙이 있는지 확인

# 3. 루트 레벨 커스텀 파일 확인
kubectl exec -n wp deploy/wp-wordpress -- ls -la /var/www/html/ | grep -v "^d" | grep -v "wp-"
# → 커스텀 파일들 확인

# 4. wp-content 하위 확인
kubectl exec -n wp deploy/wp-wordpress -- ls -la /var/www/html/wp-content/
# → languages/, mu-plugins/ 등 확인
```

## 💡 권장사항

### 회사 사이트 (dyibs.com)의 경우

1. **.htaccess 보존 필수** ⭐⭐⭐
   - 보안 규칙이나 리다이렉트가 있을 가능성 높음
   - 먼저 확인하고 커스터마이징이 있으면 NFS에 보존

2. **robots.txt 보존 권장** ⭐⭐
   - SEO가 중요한 회사 사이트
   - 커스텀 규칙이 있으면 보존

3. **파일 확인 후 결정**
   - 위의 체크리스트로 현재 파일 확인
   - 커스터마이징이 있으면 보존, 기본값이면 보존 불필요

## 🎯 다음 단계

1. 현재 파일 확인
2. .htaccess와 robots.txt 내용 검토
3. 커스터마이징이 있으면 NFS 보존 설정 추가
4. Pod 재시작하여 적용

보존이 필요한 파일을 확인하시면 설정을 추가해드리겠습니다!