# Bootc Build Scenarios

A collection of examples demonstrating how to build bootc images across different environments and tools, including RHEL and non-RHEL systems OpenShift with Tekton and GitHub Actions. This repository serves as a practical guide for learning and comparing various workflows for bootc OS image creation.

## What is Bootc?

Bootc is a technology that enables transactional, in-place operating system updates using OCI/Docker container images by using bootable containers (container images that include the Kernel). It applies the successful container layering model to bootable host systems, using standard OCI/Docker containers as a transport and delivery format for base operating system updates.

![bootc-system-update](doc/bootc-system-update.png)

## Repository Structure

This repository contains various scenarios and examples organized by platform and build methodology:

```
bootc-build-scenarios/
├── build/                # Build scenarios
├── doc/                  # Documentation files
├── images/               # Sample image definitions
└── tools/
    └── extract-oci-diskimage/  # Utility to extract disk images from OCI artifacts
```

## Scenarios Covered

These are the scenarios that you can find in this repo:

  * Build using RHEL systems
  * Build using Non-RHEL systems
  * Build using OpenShift Pipelines
  * Build using GitHub Actions

## Quick Start

1. Clone this repository:
```bash
git clone https://github.com/luisarizmendi/bootc-build-scenarios.git
cd bootc-build-scenarios
```

2. Choose a scenario that matches your environment and requirements

3. Follow the README in the specific scenario directory

