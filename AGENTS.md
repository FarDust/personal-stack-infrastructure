# Infrastructure Repository Guidance

This repository manages infrastructure with Terraform Cloud. Read this file before using Terraform, CI tooling, cost-estimation tools, or the official HashiCorp Terraform MCP server.

## Terraform Cloud Workflow

- Treat Terraform Cloud as the source of truth for infrastructure plans and applies.
- Use full Terraform Cloud plans that evaluate the complete configuration.
- A plan created with `-target` is invalid for review, merge, or apply. Replace it with a full plan before continuing.
- Use speculative plans for investigation and review. Use plan and apply workflows that match the intended source revision.

## VCS and CI Delivery

- Use VCS and CI delivery to produce reviewable Terraform Cloud plans for proposed and merged revisions.
- Before merge or apply, confirm the plan has been reviewed, required checks are clean, the resource scope is expected, and the cost is acceptable.
- Apply only a reviewed, approvable plan that corresponds to the intended revision.

## Cost Ceiling

- Keep total recurring infrastructure cost at or below USD 30 per month.
- Review cost before merge and apply using a Terraform Cloud estimate, provider pricing, Infracost, or another explicit source.
- Record the cost signal and any material assumption in the handoff.

## Official Terraform MCP

- Use the official HashiCorp Terraform MCP server for permitted discovery of registries, projects, workspaces, variables, runs, plans, costs, logs, and policy results.
- Use the MCP workflow to inspect the current state, create or review speculative plans, and apply an approved Terraform Cloud plan when authorized.
- Keep credentials in approved secret storage. Never place credentials or sensitive values in repository files, plans, logs, or handoff notes.

## Objective-Based Plan Evaluation

Evaluate a plan by the evidence it produces, not by whether a command exits successfully. Confirm:

- The plan evaluates the complete configuration and contains no targeting.
- The policy and check result is acceptable.
- The planned change type, including creates, updates, deletes, and replacements, matches the requested scope.
- The cost signal is within the USD 30 per month ceiling.
- The plan was generated from the intended revision.
- The expected observable postconditions are clear and can be verified after apply.

## Completion Evidence

After apply, verify and record the Terraform Cloud run result, expected outputs, actual resource scope, applicable service health, cost signal, source revision, and observable postconditions. Include this evidence and the final result in the handoff. A successful command or completed run alone is not completion.
