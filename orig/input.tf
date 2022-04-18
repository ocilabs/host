# Copyright (c) 2020 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

variable "input" {
    type = object({
      internet = string,
      nat      = string,
      ipv6     = bool,
      osn      = string
    })
    description = "Resources identifier from resident module"
}

variable "tenancy" {
  type = object({
    id      = string,
    class   = number,
    buckets = string,
    region  = map(string)
  })
  description = "Tenancy Configuration"
}

variable "assets" {
  type = object({
    resident = any
    network  = any
  })
  description = "Retrieve asset identifier"
}

variable "resident" {
  type = object({
    owner          = string,
    name           = string,
    label          = string,
    stage          = number,
    region         = map(string)
    compartments   = map(number),
    repository     = string,
    groups         = map(string),
    policies       = map(any),
    notifications  = map(any),
    tag_namespaces = map(number),
    tags           = any
  })
  description = "Service Configuration"
}

variable "network" {
  type = object({
    name         = string,
    region       = string,
    display_name = string,
    dns_label    = string,
    compartment  = string,
    stage        = number,
    cidr         = string,
    gateways     = any,
    route_tables = map(any),
    subnets      = map(any),
    security_lists = any
  })
  description = "Network Configuration"
}
    
# original input

variable "host_name" {
    type = string
    description   = "Identify the host, use a unique name"
    validation {
        condition     = length(regexall("^[A-Za-z][A-Za-z0-9]{1,14}$", var.options.name)) > 0
        error_message = "The label variable must contain alphanumeric characters only, start with a letter, contains up to 15 letters and has at least three consonants."
    }
}

variable "config" {
    type = object({
        service_id     = string,
        compartment_id = string,
        bundle_type    = number,
        subnet_ids     = list(string),
        bastion_id     = string,
        ad_number      = number,
        defined_tags   = map(any),
        freeform_tags  = map(any)
    })
    description = "Service Configuration"
}

variable "host" {
    type = object({
        shape = string,
        image = string,
        disk  = string,
        nic   = string
    })
    description = "Host Configuration"
}

variable "ssh" {
    type = object({
        enable          = bool,
        type            = string,
        ttl_in_seconds  = number,
        target_port     = number
    })
}

/*
variable "notification" {
    type = object({
        notification_enabled = bool,    # Whether to enable ONS notification for the operator host (false)
        notification_endpoint = string, # The subscription notification endpoint. Email address to be notified (null)
        notification_protocol = string, # The notification protocol used ("EMAIL")
        notification_topic = string,    # The name of the notification topic ("operator")
    })
}
*/
