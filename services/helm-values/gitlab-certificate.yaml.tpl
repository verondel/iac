apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gitlab-tls
  namespace: gitlab
spec:
  secretName: gitlab-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - gitlab.${domain}
    - registry.${domain}
    - minio.${domain}