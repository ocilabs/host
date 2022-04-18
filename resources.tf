# Copyright (c) 2020 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

############
# Instance
############
resource "oci_core_instance" "instance" {
  count = var.instance_count
  // If no explicit AD number, spread instances on all ADs in round-robin. Looping to the first when last AD is reached
  availability_domain  = var.ad_number == null ? element(local.ADs, count.index) : element(local.ADs, var.ad_number - 1)
  compartment_id       = data.oci_identity_compartments.application.compartments[0].id
  display_name         = var.instance_display_name == "" ? "" : var.instance_count != 1 ? "${var.instance_display_name}_${count.index + 1}" : var.instance_display_name
  extended_metadata    = var.extended_metadata
  ipxe_script          = var.ipxe_script
  preserve_boot_volume = var.preserve_boot_volume
  state                = var.instance_state
  shape                = var.shape
  shape_config {
    // If shape name contains ".Flex" and instance_flex inputs are not null, use instance_flex inputs values for shape_config block
    // Else use values from data.oci_core_shapes.current_ad for var.shape
    memory_in_gbs             = local.shape_is_flex == true && var.instance_flex_memory_in_gbs != null ? var.instance_flex_memory_in_gbs : local.shapes_config[var.shape]["memory_in_gbs"]
    ocpus                     = local.shape_is_flex == true && var.instance_flex_ocpus != null ? var.instance_flex_ocpus : local.shapes_config[var.shape]["ocpus"]
    baseline_ocpu_utilization = var.baseline_ocpu_utilization
  }

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false

    # ! provider seems to have a bug with plugin_config stanzas below
    // this configuration is applied at first resource creation
    // subsequent updates are detected as changes by terraform but seems to be ignored by the provider ...
    plugins_config {
      desired_state = var.cloud_agent_plugins.autonomous_linux
      name          = "Oracle Autonomous Linux"
    }
    plugins_config {
      desired_state = var.cloud_agent_plugins.bastion
      name          = "Bastion"
    }
    plugins_config {
      desired_state = var.cloud_agent_plugins.block_volume_mgmt
      name          = "Block Volume Management"
    }
    plugins_config {
      desired_state = var.cloud_agent_plugins.custom_logs
      name          = "Custom Logs Monitoring"
    }
    plugins_config {
      desired_state = var.cloud_agent_plugins.management
      name          = "Management Agent"
    }
    plugins_config {
      desired_state = var.cloud_agent_plugins.monitoring
      name          = "Compute Instance Monitoring"
    }
    plugins_config {
      desired_state = var.cloud_agent_plugins.osms
      name          = "OS Management Service Agent"
    }
    plugins_config {
      desired_state = var.cloud_agent_plugins.run_command
      name          = "Compute Instance Run Command"
    }
    plugins_config {
      desired_state = var.cloud_agent_plugins.vulnerability_scanning
      name          = "Vulnerability Scanning"
    }
  }

  create_vnic_details {
    assign_public_ip = var.public_ip == "NONE" ? var.assign_public_ip : false
    display_name     = var.vnic_name == "" ? "" : var.instance_count != "1" ? "${var.vnic_name}_${count.index + 1}" : var.vnic_name
    hostname_label   = var.hostname_label == "" ? "" : var.instance_count != "1" ? "${var.hostname_label}-${count.index + 1}" : var.hostname_label
    private_ip = element(
      concat(var.private_ips, [""]),
      length(var.private_ips) == 0 ? 0 : count.index,
    )
    skip_source_dest_check = var.skip_source_dest_check
    // Current implementation requires providing a list of subnets when using ad-specific subnets
    subnet_id = data.oci_core_subnet.host[count.index % length(data.oci_core_subnet.host.*.id)].id
    nsg_ids   = var.primary_vnic_nsg_ids

    freeform_tags = local.merged_freeform_tags
    defined_tags  = var.assets.resident.defined_tags
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_keys != null ? var.ssh_public_keys : file(var.ssh_authorized_keys)
    user_data           = var.user_data
  }

  source_details {
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
    source_id               = var.source_ocid
    source_type             = var.source_type
  }

  freeform_tags = local.merged_freeform_tags
  defined_tags  = var.assets.resident.defined_tags

  timeouts {
    create = var.instance_timeout
  }
}

resource "oci_core_public_ip" "public_ip" {
  count          = var.public_ip == "NONE" ? 0 : var.instance_count
  compartment_id = data.oci_identity_compartments.application.compartments[0].id
  lifetime       = var.public_ip

  display_name  = var.public_ip_display_name != null ? var.public_ip_display_name : oci_core_instance.instance[count.index].display_name
  private_ip_id = data.oci_core_private_ips.host[count.index].private_ips[0].id
  # public_ip_pool_id = oci_core_public_ip_pool.test_public_ip_pool.id # * (BYOIP CIDR Blocks) are not supported yet by this module.

  freeform_tags = local.merged_freeform_tags
  defined_tags  = var.assets.resident.defined_tags
}

#############
# Boot Volume
#############

# Assign a backup policy to instance's boot volume

resource "oci_core_volume_backup_policy_assignment" "boot_volume_backup_policy" {
  # * The boot volume backup policy is controlled by var.boot_volume_backup_policy.
  # * You can choose between OCI default backup policies : gold, silver, bronze.
  # * If you set the variable to "disabled", no backup policy will be applied to the boot volume.
  count     = var.boot_volume_backup_policy != "disabled" ? var.instance_count : 0
  asset_id  = oci_core_instance.instance.*.boot_volume_id[count.index]
  policy_id = local.backup_policies[var.boot_volume_backup_policy]
}

#########
# Volume
#########
resource "oci_core_volume" "volume" {
  count               = var.instance_count * length(var.block_storage_sizes_in_gbs)
  availability_domain = oci_core_instance.instance[count.index % var.instance_count].availability_domain
  compartment_id      = data.oci_identity_compartments.application.compartments[0].id
  display_name        = "${oci_core_instance.instance[count.index % var.instance_count].display_name}_volume${floor(count.index / var.instance_count)}"
  size_in_gbs = element(
    var.block_storage_sizes_in_gbs,
    floor(count.index / var.instance_count),
  )
  freeform_tags = local.merged_freeform_tags
  defined_tags  = var.assets.resident.defined_tags
}

####################
# Volume Attachment
####################
resource "oci_core_volume_attachment" "volume_attachment" {
  count           = var.instance_count * length(var.block_storage_sizes_in_gbs)
  attachment_type = var.attachment_type
  instance_id     = oci_core_instance.instance[count.index % var.instance_count].id
  volume_id       = oci_core_volume.volume[count.index].id
  use_chap        = var.use_chap
}