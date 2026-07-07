# create-umi-script

Ansible playbook to create Azure User Managed Identities (UMIs) with the required RBAC roles. Designed to be run via Semaphore pulling from this Git repository.

## Repository structure

```
create_umi.yml       # Main Ansible playbook
vars/umi.yml         # Variable template
```

## RBAC roles assigned

The playbook assigns the following roles to the UMI at subscription scope:

- Application Group Contributor
- Backup Operator
- Desktop Virtualization Application Group Contributor
- Desktop Virtualization Host Pool Contributor
- Desktop Virtualization Workspace Contributor
- Key Vault Data Access Administrator
- MS-ISR: NetApp Contributor
- MS-ISR: Virtual Machine Contributor
- Network Contributor
- Reader
- MS-ISR: Recovery Services Contributor
- MS-ISR: Marketplace Ordering Contributor

## Naming conventions

| Resource | Pattern | Example |
|---|---|---|
| UMI | `umi-pdev-<mission-plane-name>-iac` | `umi-pdev-avd-iac` |
| Resource Group | `rg-mp-<mission-plane-name>-umi` | `rg-mp-avd-umi` |

## Prerequisites

### Prerequisites

The Semaphore runner requires:

- **Azure CLI** (`az`) installed and accessible
- **Azure Government cloud** — the playbook sets `az cloud set --name AzureUSGovernment` automatically
- No Ansible collections required — the playbook uses `az` CLI commands directly, avoiding any `azure.azcollection` dependency

The playbook authenticates to Azure using a User Assigned Managed Identity (UAMI). The following are hardcoded in the playbook and require no Semaphore environment configuration:

| Variable | Value |
|---|---|
| `AZURE_AUTH_SOURCE` | `msi` |
| `AZURE_CLIENT_ID` | `e8ea2483-8b75-4856-ae04-a53eaa9ef940` |

The Semaphore runner must have the UAMI (`e8ea2483-8b75-4856-ae04-a53eaa9ef940`) assigned to it, and that identity must have sufficient permissions to create resource groups, managed identities, and assign RBAC roles in the target subscription.

## Variables

| Variable | Required | Description | Example |
|---|---|---|---|
| `subscription_id` | Survey | Azure subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `mission_plane_name` | Survey | Mission plane name (lowercase) — drives all derived resource names | `avd` |
| `resource_group` | Derived | `rg-mp-{{ mission_plane_name }}-umi` — set automatically | `rg-mp-avd-umi` |
| `umi_name` | Derived | `umi-pdev-{{ mission_plane_name }}-iac` — set automatically | `umi-pdev-avd-iac` |
| `location` | Fixed | Always `usgovvirginia` — set in the playbook | `usgovvirginia` |
| `assignment_scope` | No | Scope for role assignments, defaults to subscription scope | `/subscriptions/{{ subscription_id }}` |

## Running via Semaphore

1. **Add this repository** as a Git repository in Semaphore.
2. **Ensure the Semaphore runner** has the UAMI `e8ea2483-8b75-4856-ae04-a53eaa9ef940` assigned. No secrets or environment variables are required — authentication is handled via managed identity.
3. **Create a task template** with:
   - Repository: this repo
   - Playbook: `create_umi.yml`
4. **Add the following surveys** to the task template so operators are prompted at run time:

   | Survey question | Variable | Type |
   |---|---|---|
   | Subscription ID | `subscription_id` | Text |
   | Mission Plane Name | `mission_plane_name` | Text |

   > `resource_group`, `umi_name`, and `location` are all derived automatically from `mission_plane_name` — no additional surveys needed.

5. **Run the task.** Semaphore will prompt for the three survey values, pull the latest playbook from Git, and execute it.

## Running manually

```bash
ansible-playbook create_umi.yml \
  -e subscription_id=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  -e mission_plane_name=avd
```

## Notes

- The playbook is idempotent — re-running it will not duplicate the UMI or role assignments.
- Custom `MS-ISR:` roles must already exist in the target subscription. If a role is not found the playbook will warn and continue rather than fail.
- A summary of the created UMI and assigned roles is printed at the end of each run.
