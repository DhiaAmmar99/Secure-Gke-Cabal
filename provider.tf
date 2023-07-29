terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.8.0"
    }
  }
}


provider "google" {
  region      = "europe-west9"
  project     = "cabal-archi"
  credentials = file("cabal-archi-1b08eec779f2.json")

}