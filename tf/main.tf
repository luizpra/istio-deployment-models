provider "kind" {}

locals {
    # The default node image is kindest/node:v1.25.3
    # The latest node image is kindest/node:v1.27.1
    # node_image = "kindest/node:v1.27.1"
    node_image = "kindest/node:v1.25.3"
}

resource "kind_cluster" "external" {
    name = "external"
    node_image = local.node_image
    wait_for_ready = true
}

resource "kind_cluster" "remote-one" {
    name = "remote-one"
    node_image = local.node_image
    wait_for_ready = true
}

resource "kind_cluster" "remote-two" {
    name = "remote-two"
    node_image = local.node_image
    wait_for_ready = true
}