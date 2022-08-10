output "bastion_username" {
  value = data.external.gcloud_set_bastion_password.result.username
}

output "bastion_password" {
  value = data.external.gcloud_set_bastion_password.result.password
}