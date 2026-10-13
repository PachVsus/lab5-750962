variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "expected_account_id" {
  description = "Cuenta Academy verificada por el alumno. Evita desplegar en otra cuenta."
  type        = string
  default     = "679322737424"
}

variable "demo_threshold_bpm" {
  description = "Umbral de demostracion; no representa una evaluacion medica."
  type        = number
  default     = 120
  validation {
    condition     = var.demo_threshold_bpm >= 20 && var.demo_threshold_bpm <= 250 && floor(var.demo_threshold_bpm) == var.demo_threshold_bpm
    error_message = "El umbral debe ser un entero entre 20 y 250."
  }
}
