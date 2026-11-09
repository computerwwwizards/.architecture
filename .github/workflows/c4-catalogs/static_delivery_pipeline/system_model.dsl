developer = person "Developer" "Writes code, commits changes, and triggers pipeline workflows."
tech_lead = person "Tech Lead / Approver" "Reviews changes and holds elevated permissions to unblock deployments at the Environment Gate."

static_web_build = softwareSystem "Static Web Build" {
    source_repo = container "Source Code Repository" "Stores authoritative, version-controlled source code." "Git Object Database" {
        tags "Database"
    }
    build_job = container "Build Job Runner" "Executes linting, compilation, and artifact packaging." "GitHub Actions Runner (VM)" {
        tags "Service"
    }
    env_gate = container "Environment Protection Gate" "Pauses pipeline execution to enforce manual reviewer approvals (Separation of Duties)." "GitHub Environments" {
        tags "Gate"
    }
    deploy_job = container "Deploy Job Runner" "Ephemeral runner dedicated to deployment orchestration." "GitHub Actions Runner (VM)" {
        tags "Service"
    }
}

cache_bucket = softwareSystem "Cache Bucket" "Stores persistent build dependencies and incremental caches." {
    tags "Storage" "External System"
}
artifact_bucket = softwareSystem "Pipeline Artifact Store" "Immutable object store holding compiled build artifacts." {
    tags "Storage" "External System"
}
gh_pages = softwareSystem "GitHub Pages" "Static web hosting bucket and edge delivery platform." {
    tags "Storage" "External System"
}

// Relationships
developer -> source_repo "Pushes commits to" "Git / HTTPS"
developer -> build_job "Manually triggers workflow execution via" "GitHub UI (workflow_dispatch)"

tech_lead -> env_gate "Provides deployment approval (proof of presence)" "GitHub UI / API"
tech_lead -> build_job "Can also manually trigger workflow execution via" "GitHub UI (workflow_dispatch)"
tech_lead -> source_repo "Pushes commits to (and can self-approve)" "Git / HTTPS"

build_job -> source_repo "Fetches source code from" "Git / HTTPS"
build_job -> cache_bucket "Restores and saves dependency caches" "HTTPS / Cache API"
cache_bucket -> build_job "Returns cache payload to" "HTTPS" 
build_job -> artifact_bucket "Uploads compiled build artifacts" "HTTPS / Actions Artifact API"

build_job -> env_gate "Requests deployment to protected environment"
env_gate -> deploy_job "Unblocks execution of"

deploy_job -> artifact_bucket "Downloads verified build artifacts" "HTTPS / Actions Artifact API"
deploy_job -> gh_pages "Publishes compiled static bundle to" "HTTPS / Pages Deployment API"
