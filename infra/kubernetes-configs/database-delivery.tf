resource "kubernetes_role_v1" "database_bootstrap" {
  metadata {
    name      = "database-bootstrap"
    namespace = "fiap-data-bootstrap"
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "create", "update", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "events"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["external-secrets.io"]
    resources  = ["externalsecrets"]
    verbs      = ["get", "list", "watch"]
  }
  depends_on = [kubernetes_namespace_v1.from_yaml]
}
resource "kubernetes_role_binding_v1" "database_bootstrap" {
  metadata {
    name      = "database-bootstrap"
    namespace = "fiap-data-bootstrap"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.database_bootstrap.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "fiap:data-bootstrap"
    api_group = "rbac.authorization.k8s.io"
  }
}
