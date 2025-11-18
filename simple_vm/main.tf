module "simple_vm" {
  source = "github.com/ugieiris/tf-module-gcp-ceins?ref=v21.0.0"

  project_id = "tec-iaasint-s-ws49" #TODO

  instance_base_name = "simplevm"
  instance_type      = "n2-custom-2-4096"
  description        = "Simple VM"
  instance_profile   = "test"
  os_image_family    = "iaas-rhel-9"

  metadata = {
    iaas-setup-env = "s"
  }
}
