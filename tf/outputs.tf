output "external-context" {
  value = "kind-${kind_cluster.external.name}"
}

output "remote-one-context" {
  value = "kind-${kind_cluster.remote-one.name}"
}

output "remote-two-context" {
  value = "kind-${kind_cluster.remote-two.name}"
}

