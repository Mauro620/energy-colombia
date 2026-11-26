variable "region" {
  type    = string
  default = "us-east-1"
}

variable "allowed_cidrs" {
  description = "IPs (/32) con acceso al puerto 5432. Obtener la propia con infra/aws/mi_ip.sh"
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", c)) && c != "0.0.0.0/0"])
    error_message = "allowed_cidrs debe tener al menos un CIDR /32 (por ejemplo 203.0.113.7/32); 0.0.0.0/0 no se permite."
  }
}

variable "engine_version" {
  description = "Version de PostgreSQL en RDS. Misma version MAYOR que POSTGRES_VERSION de .env (16)"
  type        = string
  default     = "16.13"
}

variable "db_name" {
  type    = string
  default = "energia_db"
}

variable "db_username" {
  type    = string
  default = "energia_admin"
}

variable "proteccion" {
  description = "deletion_protection de la instancia. Poner false solo para destruir (infra/aws/destruir.sh lo hace)"
  type        = bool
  default     = true
}

variable "omitir_snapshot_final" {
  description = "true = destruir sin snapshot final"
  type        = bool
  default     = false
}
