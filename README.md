# WordPress Helm Chart

Production-ready WordPress deployment with Nginx + PHP-FPM, MariaDB, and optional NFS storage support.

## Features

- **Modern Stack**: Nginx + PHP-FPM architecture for better performance
- **Secure**: SSL/TLS support with cert-manager integration
- **Persistent**: Supports local PVC and NFS for data persistence
- **Scalable**: Resource limits and requests configured
- **Flexible**: Highly configurable via values.yaml

## Architecture

```
┌─────────────────────────────────────┐
│  Ingress (Nginx Ingress Controller) │
│  - SSL/TLS Termination              │
│  - HTTPS Redirect                    │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│  WordPress Pod                      │
│  ┌──────────────────────────────┐   │
│  │ Nginx Container              │   │
│  │ - Static file serving        │   │
│  │ - FastCGI proxy              │   │
│  └──────────┬───────────────────┘   │
│             │                        │
│  ┌──────────▼───────────────────┐   │
│  │ PHP-FPM Container            │   │
│  │ - WordPress application      │   │
│  └──────────┬───────────────────┘   │
│             │                        │
│  ┌──────────▼───────────────────┐   │
│  │ Volumes:                     │   │
│  │ - local-path PVC (core)      │   │
│  │ - NFS (wp-content, optional) │   │
│  │ - ConfigMap (wp-config.php)  │   │
│  └──────────────────────────────┘   │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│  MariaDB StatefulSet                │
│  - Persistent data storage           │
└─────────────────────────────────────┘
```

## Prerequisites

- Kubernetes cluster (1.19+)
- Helm 3.x
- Nginx Ingress Controller
- cert-manager (for SSL/TLS)
- Storage provisioner (local-path or similar)
- (Optional) NFS server for shared storage

## Quick Start

### 1. Clone the repository

```bash
git clone <repository-url>
cd wordpress
```

### 2. Create your values file

```bash
cp values.yaml.example values.yaml
```

### 3. Configure required values

Edit `values.yaml` and set:

```yaml
wordpress:
  # REQUIRED: WordPress admin password
  wordpressPassword: "your-secure-password"
  
  # REQUIRED: Your domain
  ingress:
    hosts:
      - host: your-domain.com
    tls:
      - secretName: your-domain-tls
        hosts:
          - your-domain.com
  
  # REQUIRED: Generate security keys
  # Visit: https://api.wordpress.org/secret-key/1.1/salt/
  authKey: "your-generated-key"
  secureAuthKey: "your-generated-key"
  # ... (copy all 8 keys)

mariadb:
  auth:
    # REQUIRED: Database passwords
    rootPassword: "your-db-root-password"
    password: "your-db-password"
```

### 4. Generate WordPress Security Keys

Visit [WordPress Salt Generator](https://api.wordpress.org/secret-key/1.1/salt/) and copy the generated keys to your `values.yaml`:

```bash
curl https://api.wordpress.org/secret-key/1.1/salt/
```

### 5. Install the chart

```bash
# Create namespace
kubectl create namespace wordpress

# Install
helm install wp . -n wordpress -f values.yaml

# Or upgrade
helm upgrade --install wp . -n wordpress -f values.yaml
```

### 6. Verify installation

```bash
# Check pods
kubectl get pods -n wordpress

# Expected output:
# NAME                            READY   STATUS    RESTARTS   AGE
# wp-wordpress-xxxxx-xxxxx        2/2     Running   0          2m
# wp-wordpress-mariadb-0          1/1     Running   0          2m

# Check ingress
kubectl get ingress -n wordpress
```

## Configuration

### Storage Options

#### Option 1: Local Path Storage (Default)

```yaml
wordpress:
  persistence:
    enabled: true
    storageClass: "local-path"
    size: 500Mi
```

#### Option 2: NFS Storage (Recommended for Production)

```yaml
wordpress:
  nfs:
    enabled: true
    server: "your-nas-server.local"
    path: "/path/to/wordpress"
    size: "2Gi"
    preservePaths:
      wpContent: true
      wpConfig: true
```

### Resource Configuration

```yaml
wordpress:
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 250m
      memory: 512Mi

mariadb:
  primary:
    resources:
      limits:
        cpu: 1000m
        memory: 1Gi
      requests:
        cpu: 250m
        memory: 512Mi
```

### Nginx Configuration

```yaml
wordpress:
  nginx:
    version: "1.29.0"
    maxUploadSize: "64M"
    fastcgiCache:
      enabled: false  # Enable for high-traffic sites
```

## Advanced Configuration

### Using Existing Secrets

Instead of storing passwords in `values.yaml`, use Kubernetes Secrets:

```bash
# Create secret
kubectl create secret generic wp-passwords -n wordpress \
  --from-literal=wordpress-password='your-password' \
  --from-literal=mariadb-password='db-password' \
  --from-literal=mariadb-root-password='db-root-password'

# Reference in values.yaml
mariadb:
  auth:
    existingSecret: "wp-passwords"
```

### Multiple Values Files

```bash
# Separate public and secret configurations
helm install wp . -n wordpress \
  -f values.yaml.example \
  -f values-secret.yaml
```

### Command Line Overrides

```bash
helm install wp . -n wordpress \
  --set wordpress.wordpressPassword='your-password' \
  --set mariadb.auth.password='db-password' \
  --set mariadb.auth.rootPassword='db-root-password'
```

## Maintenance

### Backup

```bash
# Backup database
kubectl exec -n wordpress wp-wordpress-mariadb-0 -- \
  mysqldump -u root -p'your-root-password' wordpress > backup.sql

# Backup wp-content (if using NFS)
# Your NFS server should have its own backup strategy
```

### Upgrade WordPress

```yaml
# Update image tag in values.yaml
wordpress:
  image:
    tag: "6.8.4-php8.4-fpm"  # New version

# Apply upgrade
helm upgrade wp . -n wordpress -f values.yaml
```

### Scale Resources

```yaml
# Increase resources
wordpress:
  resources:
    limits:
      cpu: 2000m
      memory: 2Gi

# Apply changes
helm upgrade wp . -n wordpress -f values.yaml
```

## Troubleshooting

### Pod not starting

```bash
# Check pod status
kubectl describe pod -n wordpress wp-wordpress-xxxxx

# Check logs
kubectl logs -n wordpress wp-wordpress-xxxxx -c nginx
kubectl logs -n wordpress wp-wordpress-xxxxx -c wordpress
```

### Database connection error

```bash
# Verify database is running
kubectl get pods -n wordpress

# Check database credentials
kubectl exec -n wordpress wp-wordpress-mariadb-0 -- \
  mariadb -u wordpress -p'your-password' -e "SHOW DATABASES;"
```

### Certificate issues

```bash
# Check certificate status
kubectl get certificate -n wordpress

# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager
```

## Uninstallation

```bash
# Uninstall release
helm uninstall wp -n wordpress

# Delete PVCs (optional - this will delete all data!)
kubectl delete pvc -n wordpress --all

# Delete namespace
kubectl delete namespace wordpress
```

## License

This Helm chart is provided as-is without warranty.

## Contributing

Issues and pull requests are welcome!
