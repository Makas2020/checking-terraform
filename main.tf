# This Terraform code inspired by https://github.com/terraform-google-modules/terraform-google-bastion-host.

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

data "google_compute_network" "network" {
  name = var.network_name
}

data "google_compute_subnetwork" "subnet" {
  name   = var.subnet_name
  region = var.region
}

resource "google_service_account" "bastion_host" {
  project      = var.project
  account_id   = var.service_account_name
  display_name = "Service Account for Bastion"
}

resource "google_compute_instance" "bastion_host" {
  name         = var.name
  machine_type = var.machine_type

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  network_interface {
    subnetwork = data.google_compute_subnetwork.subnet.self_link
    access_config {}
  }

  service_account {
    email  = google_service_account.bastion_host.email
    scopes = var.scopes
  }

  tags = [var.tag]
  labels = merge(var.labels, {
    git_commit           = "6754838438d6f6fb38917ac490a452841f2c28d5"
    git_file             = "main_tf"
    git_last_modified_at = "2022-08-10-18-49-28"
    git_last_modified_by = "65673629akas2020"
    git_modifiers        = "65673629akas2020"
    git_org              = "Makas2020"
    git_repo             = "checking-terraform"
    yor_trace            = "181f0de5-a56d-424a-817a-125c104acd33"
  })
  metadata = var.metadata
}

resource "google_compute_firewall" "allow_from_iap_to_bastion" {
  project = var.project
  name    = var.fw_name_allow_iap_to_bastion
  network = data.google_compute_network.network.self_link

  allow {
    protocol = "tcp"
    ports    = ["3389"]
  }

  # https://cloud.google.com/iap/docs/using-tcp-forwarding#before_you_begin
  # This range is needed to allow IAP to access the bastion host
  source_ranges = ["35.235.240.0/20"]

  target_tags = [var.tag]
}

resource "google_compute_firewall" "allow_access_from_bastion" {
  project = var.project
  name    = var.fw_name_allow_mgmt_from_bastion
  network = data.google_compute_network.network.self_link

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "3389"]
  }

  # Allow management traffic from bastion
  source_tags = [var.tag]
}

# Updates the IAM policy to grant roles/iap.tunnelResourceAccessor to specificed members, which is required for IAP
resource "google_iap_tunnel_instance_iam_binding" "enable_iap" {
  project    = var.project
  zone       = var.zone
  instance   = var.name
  role       = "roles/iap.tunnelResourceAccessor"
  members    = var.members
  depends_on = [google_compute_instance.bastion_host]
}

# Allow accounts specified in var.members to use the newly created service account
resource "google_service_account_iam_binding" "bastion_sa_user" {
  service_account_id = google_service_account.bastion_host.id
  role               = "roles/iam.serviceAccountUser"
  members            = var.members
}

# Grant roles specified in var.service_account_roles to the newly created service account
resource "google_project_iam_member" "bastion_sa_bindings" {
  for_each = toset(var.service_account_roles)

  project = var.project
  role    = each.key
  member  = "serviceAccount:${google_service_account.bastion_host.email}"
}

# This time_sleep resource will add a 60 second delay the bastion to boot before attempting to set the password
resource "time_sleep" "wait_60_seconds" {
  create_duration = "60s"
  depends_on      = [google_compute_instance.bastion_host]
}

# This data source will run the gcloud tool to set the password on our bastion. The results are returned JSON formatted,
# which is a requirement for the external data source. time_sleep.wait_60_seconds is specificed as a dependency so the
# bastion host has time to boot before the pasword reset is attempted.
data "external" "gcloud_set_bastion_password" {
  program    = ["bash", "-c", "gcloud compute reset-windows-password ${var.name} --user=${var.username} --format=json --quiet"]
  depends_on = [time_sleep.wait_60_seconds]
}
