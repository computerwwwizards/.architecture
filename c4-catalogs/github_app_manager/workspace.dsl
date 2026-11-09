workspace "GitHub App Creator, IAM & Agentic Webhook Platform" "End-to-end GitHub App factory, secret vault, dynamic shard orchestrator, and high-throughput webhook gateway on Cloudflare" {
!identifiers hierarchical
model {
tenant = person "Developer / Tenant" "Creates GitHub Apps via the manifest flow, manages IAM/tokens, and configures sharding tiers."
github = softwareSystem "GitHub" "Hosts GitHub Apps, executes the App Manifest creation flow, and dispatches high-volume agentic webhooks." {
tags "External"
}
downstreamBrain = softwareSystem "Internal Downstream Consumer / Agent Brain" "Internal Cloudflare Worker/DO (or Team B service) bound via Service Binding to process verified webhooks." {
tags "InternalSystem"
}
platform = softwareSystem "GitHub App Creator, IAM & Webhook Gateway" "Creates GitHub Apps dynamically, manages encrypted credentials & sharding lifecycles, and verifies high-throughput webhooks." {
frontendApp = container "Tenant Portal & Manifest Launcher" "Web UI that builds the GitHub App Manifest JSON, POSTs to GitHub, handles the OAuth/manifest redirect, and provides IAM controls for tier changes and revocations." "Frontend Application" {
tags "Frontend"
}
controlPlaneWorker = container "App Creator & IAM Control Plane Worker" "Orchestrates GitHub App creation, secret encryption, sharding tier migrations, and deterministic DO shard evictions." "Cloudflare Worker" {
manifestCreator = component "GitHub App Manifest Creator" "Generates manifest payloads, exchanges temporary GitHub code for App ID, PEM, Client Secret, and Webhook Secret." "TypeScript Module"
secretVaultCrypto = component "Secret Vault Encryptor" "Encrypts raw GitHub App PEM keys and Webhook Secrets (AES-GCM) before persisting to D1 or dispatching to DO shards." "Web Crypto Module"
iamLifecycleEngine = component "IAM & Shard Lifecycle Controller" "Handles token revocations, status changes, and sharding upgrades/downgrades (shared <-> per_app <-> per_installation <-> per_repo)." "TypeScript Module"
evictionCoordinator = component "Shard Eviction & Migration Coordinator" "Queries D1 for all active DO IDs tied to a registration_id and invokes bulk eviction or state migration on DO Manager." "TypeScript Module"
}
ingressWorker = container "Webhook Ingress & Router Worker" "Public webhook edge router that resolves shard routing via KV in 1 hop or falls back to D1 during the 60s KV staleness window." "Cloudflare Worker" {
payloadParser = component "Webhook Ingress & Header Parser" "Extracts X-Hub-Signature-256, X-GitHub-Delivery, app_id, installation_id, repo_id, and registration_id." "TypeScript Module"
fastKvRouter = component "Stateless Fast KV Router" "Reads sharding_type and config_version from KV (<1ms) and computes the target DO HMAC Shard ID." "TypeScript Module"
slowHmacFallback = component "Slow HMAC D1 Fallback Verifier" "Triggered when KV misses or when a DO Shard rejects a stale KV route during the 60s eviction window. Verifies against D1 and heals KV." "TypeScript Module"
}
kvCache = container "Routing KV Cache" "Stores fast-path lookup (registration_id -> sharding_type, status, config_version, mapped shard metadata). Eventually consistent (~60s)." "Cloudflare KV" {
tags "Cache"
}
d1Database = container "D1 Control-Plane & IAM Brain" "Authoritative relational store holding registration_id (PK), encrypted secrets, app metadata, sharding_type, and registry of all spawned DO Shard IDs." "Cloudflare D1 (SQLite)" {
tags "Database"
}
doManagerWorker = container "DO Manager & HMAC Shards Worker" "Private Worker (workers_dev = false) exposing a WorkerEntrypoint for shard CRUD and hosting the Durable Object namespace." "Cloudflare Worker + Durable Objects" {
tags "Internal"
doCrudEntrypoint = component "DO CRUD Manager Entrypoint" "Private RPC service (WorkerEntrypoint) for provisioning shards, injecting encrypted secrets, and executing forced deleteAll() + abort()." "WorkerEntrypoint"
hmacShardDo = component "DO HMAC Shard" "Stateful actor sharded dynamically (shared pool, per-app, per-installation, or per-repo). Caches decrypted key in RAM, checks replay cache in local SQLite, and runs timingSafeEqual." "Durable Object + SQLite"
}
}
# 1. GitHub App Creation Flow (Manifest Flow)
tenant -> platform.frontendApp "Configures new GitHub App permissions, sharding tier, and triggers creation or IAM updates" "HTTPS"
platform.frontendApp -> github "POSTs GitHub App Manifest JSON to /settings/apps/new and redirects user back with temporary code" "HTTPS Browser Redirect"
platform.frontendApp -> platform.controlPlaneWorker.manifestCreator "Submits temporary code from GitHub redirect and selected sharding configuration" "HTTPS API"
platform.controlPlaneWorker.manifestCreator -> github "Exchanges temporary code via POST /app-manifests/{code}/conversions for App ID, PEM, and Webhook Secret" "HTTPS REST"
platform.controlPlaneWorker.manifestCreator -> platform.controlPlaneWorker.secretVaultCrypto "Passes raw PEM, Client Secret, and Webhook Secret for encryption" "Internal Call"
platform.controlPlaneWorker.secretVaultCrypto -> platform.d1Database "Persists registration_id, encrypted secrets, initial sharding_type, and initial DO ID" "D1 Binding"
platform.controlPlaneWorker.secretVaultCrypto -> platform.kvCache "Populates initial fast-path routing entry (registration_id -> sharding_type, v1)" "KV Binding"
platform.controlPlaneWorker.secretVaultCrypto -> platform.doManagerWorker.doCrudEntrypoint "Provisions initial DO shard and injects encrypted secret copy" "Service Binding (RPC)"
# 2. IAM Status Change, Token Revocation & Tier Migration / Eviction Flow
platform.frontendApp -> platform.controlPlaneWorker.iamLifecycleEngine "Requests token deletion, status disable, or sharding tier upgrade/downgrade" "HTTPS API"
platform.controlPlaneWorker.iamLifecycleEngine -> platform.d1Database "Updates authoritative status/tier, increments config_version, and fetches all registered DO IDs for registration_id" "D1 Binding"
platform.controlPlaneWorker.iamLifecycleEngine -> platform.kvCache "Writes updated routing config or tombstone to KV (propagates globally in ~60s)" "KV Binding"
platform.controlPlaneWorker.iamLifecycleEngine -> platform.controlPlaneWorker.evictionCoordinator "Passes list of affected DO IDs to wipe, migrate, or tombstone" "Internal Call"
platform.controlPlaneWorker.evictionCoordinator -> platform.doManagerWorker.doCrudEntrypoint "Invokes immediate eviction or secret rotation across all target DO IDs" "Service Binding (RPC)"
platform.doManagerWorker.doCrudEntrypoint -> platform.doManagerWorker.hmacShardDo "Executes storage.deleteAll() + ctx.abort() (or sets migration tombstone) on each target shard" "DO Binding (RPC)"
# 3. Agentic Webhook Hot Path (1-Hop Steady State) & 60s Stale KV Fallback
github -> platform.ingressWorker.payloadParser "Dispatches high-volume webhooks (X-Hub-Signature-256, registration_id, installation_id, repo_id)" "HTTPS POST"
platform.ingressWorker.payloadParser -> platform.ingressWorker.fastKvRouter "Passes parsed routing identifiers and raw payload buffer" "Internal Call"
platform.ingressWorker.fastKvRouter -> platform.kvCache "Reads sharding_type and config_version (<1ms edge read)" "KV Binding"
platform.ingressWorker.fastKvRouter -> platform.doManagerWorker.hmacShardDo "1-Hop RPC to computed DO Shard ID with payload, signature, and config_version" "DO Binding (RPC)"
platform.doManagerWorker.hmacShardDo -> platform.d1Database "Lazily registers newly spawned DO ID (e.g., new repo shard) via waitUntil on first cold start" "D1 Binding"
platform.doManagerWorker.hmacShardDo -> downstreamBrain "Forwards verified webhook payload after replay check and timingSafeEqual HMAC match" "Service Binding (RPC)"
# Fallback when KV is cold OR DO Shard rejects stale KV route during 60s window
platform.ingressWorker.fastKvRouter -> platform.ingressWorker.slowHmacFallback "Falls back if KV misses OR if DO Shard returns STALE_VERSION / EVICTED during the 60s KV propagation window" "Internal Call"
platform.ingressWorker.slowHmacFallback -> platform.d1Database "Reads authoritative sharding_type, active status, and encrypted secret directly from D1" "D1 Binding"
platform.ingressWorker.slowHmacFallback -> platform.kvCache "Heals/updates local edge KV cache with fresh D1 state" "KV Binding"
platform.ingressWorker.slowHmacFallback -> downstreamBrain "Decrypts secret, runs timingSafeEqual fallback verification, and forwards verified webhook" "Service Binding (RPC)"
}
views {
systemContext platform "SystemContext" "High-level boundary showing Tenant, GitHub, the App Creator/IAM/Gateway Platform, and the Internal Downstream Brain." {
include *
autoLayout lr
}
container platform "Containers" "Container view showing Frontend Portal, App Creator & IAM Control Plane, Ingress Router, KV, D1 Brain, and DO Manager." {
include *
autoLayout lr
}
component platform.controlPlaneWorker "ControlPlaneComponents" "Internal components of the App Creator & IAM Control Plane Worker (Manifest creation, Vault Crypto, IAM & Eviction)." {
include *
include tenant
include github
include platform.frontendApp
include platform.d1Database
include platform.kvCache
include platform.doManagerWorker
autoLayout tb
}
component platform.ingressWorker "IngressComponents" "Internal components of the Webhook Ingress Worker showing the 1-hop Fast KV Router and 60s Stale KV Fallback." {
include *
include github
include platform.kvCache
include platform.d1Database
include platform.doManagerWorker
include downstreamBrain
autoLayout tb
}
component platform.doManagerWorker "DOManagerComponents" "Internal components of the private DO Manager Worker and dynamically sharded HMAC Durable Objects." {
include *
include platform.controlPlaneWorker
include platform.ingressWorker
include platform.d1Database
include downstreamBrain
autoLayout tb
}
dynamic platform "1_AppCreationManifestFlow" "Flow 1: Creating a GitHub App via Manifest Flow and provisioning encrypted secrets into D1, KV, and initial DO Shard." {
tenant -> platform.frontendApp "1. Configures new GitHub App & clicks Create"
platform.frontendApp -> github "2. POSTs Manifest JSON to GitHub & user approves"
github -> platform.frontendApp "3. Redirects back with temporary manifest code"
platform.frontendApp -> platform.controlPlaneWorker "4. Sends code and desired sharding_type"
platform.controlPlaneWorker -> github "5. Exchanges code at /app-manifests/{code}/conversions for PEM & Webhook Secret"
platform.controlPlaneWorker -> platform.d1Database "6. Encrypts secrets and stores registration_id, sharding_type, and initial DO ID"
platform.controlPlaneWorker -> platform.kvCache "7. Writes initial routing metadata (v1) to KV"
platform.controlPlaneWorker -> platform.doManagerWorker "8. Pre-warms initial DO HMAC Shard with encrypted secret"
autoLayout tb
}
dynamic platform "2_EvictionAndTierMigrationFlow" "Flow 2: Revoking a token or migrating sharding tiers (per_repo -> shared) and wiping all related DO Shards." {
tenant -> platform.frontendApp "1. Revokes app token or changes sharding tier"
platform.frontendApp -> platform.controlPlaneWorker "2. Sends IAM status/tier update for registration_id"
platform.controlPlaneWorker -> platform.d1Database "3. Updates status/tier in D1, bumps config_version, and queries all spawned DO IDs"
platform.controlPlaneWorker -> platform.doManagerWorker "4. Sends bulk eviction RPC with all related DO IDs to execute deleteAll() + abort()"
platform.controlPlaneWorker -> platform.kvCache "5. Updates KV with new config_version / status (takes up to 60s globally)"
autoLayout tb
}
dynamic platform.doManagerWorker "2b_DOManagerInternalEviction" "Flow 2b: Component-level eviction inside DO Manager Worker wiping each target DO HMAC Shard." {
platform.controlPlaneWorker.evictionCoordinator -> platform.doManagerWorker.doCrudEntrypoint "1. Invokes bulk eviction RPC with target DO IDs"
platform.doManagerWorker.doCrudEntrypoint -> platform.doManagerWorker.hmacShardDo "2. Calls storage.deleteAll() + ctx.abort() on each target DO HMAC Shard"
autoLayout tb
}
dynamic platform "3_AgenticWebhookHotPathAndFallback" "Flow 3: High-throughput 1-hop webhook verification vs. 60-second stale KV rejection & D1 fallback." {
github -> platform.ingressWorker "1. POST webhook (X-Hub-Signature-256, registration_id, repo_id)"
platform.ingressWorker -> platform.kvCache "2. Fast lookup of sharding_type and config_version"
platform.ingressWorker -> platform.doManagerWorker "3. 1-Hop RPC to computed DO HMAC Shard (safeEquals + SQLite replay check)"
platform.doManagerWorker -> downstreamBrain "4a. [Hot Path - 99.99%] Signature valid & version fresh -> Forward via Service Binding"
platform.ingressWorker -> platform.d1Database "4b. [60s Stale Window] DO Shard rejects stale KV route -> Fallback reads authoritative D1 state"
platform.ingressWorker -> platform.kvCache "5b. [60s Stale Window] Heals KV cache with fresh D1 state"
platform.ingressWorker -> downstreamBrain "6b. [60s Stale Window] Verifies HMAC via fallback and forwards via Service Binding"
autoLayout tb
}
styles {
element "Person" {
shape Person
background #1f6feb
color #ffffff
}
element "Frontend" {
shape WebBrowser
background #0969da
color #ffffff
}
element "Software System" {
background #238636
color #ffffff
}
element "External" {
background #484f58
color #ffffff
}
element "InternalSystem" {
background #0f766e
color #ffffff
}
element "Container" {
background #1f6feb
color #ffffff
}
element "Database" {
shape Cylinder
background #8957e5
color #ffffff
}
element "Cache" {
shape Pipe
background #d29922
color #ffffff
}
element "Internal" {
background #6e40c9
color #ffffff
}
element "Component" {
background #2ea043
color #ffffff
}
}
}
}
