workspace "Central Architecture Catalog" "Central repository for FINOS CALM and system models." {

    model {
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
    }

    views {
        container static_web_build "pipeline_architecture" {
    include *
    autolayout lr
    description "The pipeline architecture showing role-based access control, the Build Runner, Environment Gate, and Deploy Runner."
}

dynamic static_web_build "push_triggered_flow" {
    title "Dynamic View 1 - Push-Triggered Gated CI/CD (Team Handoff)"
    description "Developer initiates the build via push, but the pipeline pauses until a Tech Lead approves the deployment."
    
    autolayout lr

    developer -> source_repo "1. Pushes code to trigger the workflow"
    build_job -> source_repo "2. Requests checkout and fetches commit bundle"
    build_job -> cache_bucket "3. Requests cached dependencies"
    cache_bucket -> build_job "4. Returns cached files on cache hit"
    build_job -> artifact_bucket "5. Uploads compiled build artifacts"
    build_job -> cache_bucket "6. Saves updated cache (Post-run phase)"
    
    build_job -> env_gate "7. Workflow transitions to deploy job and pauses for Environment rules"
    tech_lead -> env_gate "8. Reviews changes and approves deployment (Proof of Presence)"
    env_gate -> deploy_job "9. Approval unblocks the deployment runner"

    deploy_job -> artifact_bucket "10. Downloads verified build artifact from artifact store"
    deploy_job -> gh_pages "11. Deploys static bundle and updates release pointer"
}

dynamic static_web_build "manual_dispatch_flow" {
    title "Dynamic View 2 - Manually Triggered Gated CI/CD"
    description "A Developer manually triggers the workflow, requiring a Tech Lead to approve the final deployment phase."
    
    autolayout lr

    developer -> build_job "1. Manually triggers workflow execution via GitHub UI"
    build_job -> source_repo "2. Requests checkout for the selected branch/tag"
    build_job -> cache_bucket "3. Requests cached dependencies"
    cache_bucket -> build_job "4. Returns cached files on cache hit"
    build_job -> artifact_bucket "5. Uploads compiled build artifacts"
    build_job -> cache_bucket "6. Saves updated cache (Post-run phase)"
    
    build_job -> env_gate "7. Workflow transitions to deploy job and pauses for Environment rules"
    tech_lead -> env_gate "8. Approves deployment (Proof of Presence)"
    env_gate -> deploy_job "9. Approval unblocks the deployment runner"

    deploy_job -> artifact_bucket "10. Downloads verified build artifact from artifact store"
    deploy_job -> gh_pages "11. Deploys static bundle and updates release pointer"
}

        styles {
            element "Element" {
                color "#ffffff"
            }
            element "Container" {
                background "#2563eb"
                shape RoundedBox
            }
            element "Database" {
                background "#475569"
                shape Cylinder
            }
            element "Gate" {
                background "#eab308"
                shape Hexagon
            }
            element "Storage" {
                background "#059669"
                shape Folder
            }
            element "External System" {
                background "#0f766e"
            }
            element "Person" {
                background "#0891b2"
                shape Person
            }
        }
    }
}
