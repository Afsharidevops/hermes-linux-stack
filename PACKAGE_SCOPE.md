# Package scope

This ZIP is a self-contained enhanced deployment package for the requested Hermes -> Smart Router -> gateway path. It retains the current branch Compose topology and the relevant branch reference README, while replacing the Smart Router implementation and lightweight installer/manager with the v0.2 calibrated implementation in this archive.

The default profiles are gateway + Smart Router + Hermes + Open WebUI. Optional n8n/Caddy/execution services remain represented in Compose but are not enabled by default. The calibrated routing path does not require the optional execution plugin source.

For a byte-for-byte preservation of every unrelated development helper from the upstream branch, apply the Smart Router/Compose/env changes from this archive on top of a normal Git checkout of the same branch. This package intentionally does not claim that unrelated helper scripts are exact copies of upstream.
