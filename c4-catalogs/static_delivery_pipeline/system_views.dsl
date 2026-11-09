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
