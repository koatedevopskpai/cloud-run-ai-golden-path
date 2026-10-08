terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "service_name" {
  type    = string
  default = "llm-api"
}

variable "image" {
  description = "Image to deploy. Default points at this repo's app in Artifact Registry."
  type        = string
  default     = "us-central1-docker.pkg.dev/PROJECT_ID/ai-images/llm-endpoint:latest"
}

variable "alert_email" {
  description = "Email for the burn-rate alert"
  type        = string
  default     = "ops@example.com"
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    project     = var.project_id
    environment = "prod"
    managed_by  = "terraform"
    workload    = "cloud-run-ai-golden-path"
    cost_center = "cc-gcp-platform"
  }
}

# --- Artifact Registry + runtime identity ---
resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "ai-images"
  format        = "DOCKER"
  labels        = { workload = "cloud-run-ai-golden-path", env = "prod" }
}

resource "google_service_account" "llm" {
  account_id   = "llm-api-sa"
  display_name = "llm-api runtime"
}

resource "google_artifact_registry_repository_iam_member" "reader" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.images.id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.llm.email}"
}

# --- Cloud Run v2 service (golden-path defaults) ---
resource "google_cloud_run_v2_service" "llm" {
  name                = var.service_name
  location            = var.region
  deletion_protection = false

  template {
    service_account = google_service_account.llm.email

    containers {
      image = var.image
      resources {
        limits = { cpu = "1", memory = "512Mi" }
      }
      startup_probe {
        tcp_socket { port = 8080 }
        initial_delay_seconds = 0
        period_seconds        = 5
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    timeout = "30s"

    annotations = {
      "run.googleapis.com/startup-cpu-boost"     = "true"
      "run.googleapis.com/execution-environment" = "gen2"
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.llm.location
  name     = google_cloud_run_v2_service.llm.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- SLOs + multi-window burn-rate alert ---
resource "google_monitoring_service" "llm" {
  service_id   = "${var.service_name}-slo"
  display_name = "Cloud Run AI golden path (${var.service_name})"

  basic_service {
    service_type = "CLOUD_RUN"
    service_labels = {
      service_name = google_cloud_run_v2_service.llm.name
      location     = var.region
    }
  }
}

resource "google_monitoring_slo" "availability" {
  service             = google_monitoring_service.llm.service_id
  slo_id              = "${var.service_name}-availability"
  goal                = 0.99
  rolling_period_days = 30
  basic_sli {
    availability { enabled = true }
  }
}

resource "google_monitoring_slo" "latency" {
  service             = google_monitoring_service.llm.service_id
  slo_id              = "${var.service_name}-latency"
  goal                = 0.95
  rolling_period_days = 30
  basic_sli {
    latency { threshold = "1s" }
  }
}

resource "google_monitoring_notification_channel" "email" {
  display_name = "Ops email"
  type         = "email"
  labels       = { email_address = var.alert_email }
}

resource "google_monitoring_alert_policy" "burn_rate" {
  display_name = "${var.service_name} availability burn rate"
  combiner     = "AND"

  notification_channels = [google_monitoring_notification_channel.email.name]

  conditions {
    display_name = "fast burn (5m)"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"${google_monitoring_slo.availability.name}\", 5m)"
      threshold_value = "14.4"
      duration        = "0s"
      comparison      = "COMPARISON_GT"
    }
  }
  conditions {
    display_name = "slow burn (1h)"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"${google_monitoring_slo.availability.name}\", 1h)"
      threshold_value = "14.4"
      duration        = "0s"
      comparison      = "COMPARISON_GT"
    }
  }
}

output "service_url" {
  value = google_cloud_run_v2_service.llm.uri
}