// Copyright 2017, 2021 Oracle Corporation and/or affiliates.  All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

// --- terraform provider --- 
terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

// --- Retriev meta data for host deployment --- //
data "oci_identity_compartments" "application" {
  compartment_id = var.configuration.tenancy.id
  access_level   = "ANY"
  compartment_id_in_subtree = true
  name           = try(var.configuration.application.compartment, var.configuration.resident.name)
  state          = "ACTIVE"
}

data "oci_identity_availability_domains" "host" {
  depends_on = [
    data.oci_identity_compartments.application
  ]
  compartment_id = data.oci_identity_compartments.application.compartments[0].id
}

data "oci_core_volume_backup_policies" "host" {}
// --- Retriev meta data for application compartment --- //

// --- Create a data source for compute shapes --- //
// Filter on current AD to remove duplicates and give all the shapes supported on the AD.
// This will not check quota and limits for AD requested at resource creation
data "oci_core_shapes" "current_ad" {
  compartment_id      = data.oci_identity_compartments.application.compartments[0].id
  availability_domain = var.ad_number == null ? element(local.ADs, 0) : element(local.ADs, var.ad_number - 1)
}
// --- Create a data source for compute shapes --- //

// --- Retriev ssh key from encryption module --- //
data "oci_secrets_secretbundle" "host" {
  secret_id = var.assets.encryption.secret_ids["${var.configuration.host.display_name}_secret"]
}
// --- Retriev ssh key from encryption module --- //

// --- Retriev network details --- //
data "oci_core_subnet" "host" {
  count     = length(var.subnet_ocids)
  subnet_id = element(var.subnet_ocids, count.index)
}

data "oci_core_vnic_attachments" "host" {
  count          = var.instance_count
  compartment_id = data.oci_identity_compartments.application.compartments[0].id
  instance_id    = oci_core_instance.instance[count.index].id

  depends_on = [
    oci_core_instance.instance
  ]
}

data "oci_core_private_ips" "host" {
  count   = var.instance_count
  vnic_id = data.oci_core_vnic_attachments.host[count.index].vnic_attachments[0].vnic_id

  depends_on = [
    oci_core_instance.instance
  ]
}
// --- Retriev network details --- //

// --- Instance Credentials Datasource --- //
data "oci_core_instance_credentials" "host" {
  count       = var.resource_platform != "linux" ? var.instance_count : 0
  instance_id = oci_core_instance.instance[count.index].id
}
// --- Instance Credentials Datasource --- //

locals {
  ADs = [
    // Iterate through data.oci_identity_availability_domains.host and create a list containing AD names
    for i in data.oci_identity_availability_domains.host.availability_domains : i.name
  ]
  backup_policies = {
    // Iterate through data.oci_core_volume_backup_policies.host and create a map containing name & ocid
    // This is used to specify a backup policy id by name
    for i in data.oci_core_volume_backup_policies.host.volume_backup_policies : i.display_name => i.id
  }
  module_freeform_tags = {
    # list of freeform tags, added to stack provided freeform tags
    terraformed = "Please do not edit manually"
  }
  merged_freeform_tags = merge(local.module_freeform_tags, var.assets.resident.freeform_tags)
  shapes_config = {
    // prepare data with default values for flex shapes. Used to populate shape_config block with default values
    // Iterate through data.oci_core_shapes.current_ad.shapes (this exclude duplicate data in multi-ad regions) and create a map { name = { memory_in_gbs = "xx"; ocpus = "xx" } }
    for i in data.oci_core_shapes.current_ad.shapes : i.name => {
      "memory_in_gbs" = i.memory_in_gbs
      "ocpus"         = i.ocpus
    }
  }
  shape_is_flex = length(regexall("^*.Flex", var.shape)) > 0 # evaluates to boolean true when var.shape contains .Flex
  instances_details = [
    // display name, Primary VNIC Public/Private IP for each instance
    for i in oci_core_instance.instance : <<EOT
    ${~i.display_name~}
    Primary-PublicIP: %{if i.public_ip != ""}${i.public_ip~}%{else}N/A%{endif~}
    Primary-PrivateIP: ${i.private_ip~}
    EOT
  ]
}


// Define the wait state for the data requests
resource "null_resource" "previous" {}

// This resource will destroy (potentially immediately) after null_resource.next
resource "time_sleep" "wait" {
  depends_on = [null_resource.previous]
  create_duration = "2m"
}