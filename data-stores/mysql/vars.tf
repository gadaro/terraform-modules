# For each variable defined we can export TF_VAR_[name] on the OS
variable "db_name" {
  description = "The name to use for all the data store resources"
}

variable "db_instance" {
  description = "The type of the instance to be launched"
}

variable "db_storage" {
  description = "Amount of storage to be assigned (GB)"
}

variable "db_password" {
  description = "The password for the database"
}
