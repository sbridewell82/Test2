# create-umi-script

Ansible playbook to create Azure User Managed Identities (UMIs) with the required RBAC roles. Designed to be run via Semaphore pulling from this Git repository.

## Repository structure

```
create_umi.yml       # Main Ansible playbook
vars/umi.yml         # Variable template
requirements.yml     # Ansible Galaxy collection dependencies
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
| UMI | `umi-<env>-<purpose>` | `umi-prod-avd` |
| Resource Group | `rg-mp-<mission-plane-name>-umi` | `rg-mp-avd-umi` |

## Prerequisites

### Ansible collections

Install the required Azure collection before running:

```bash
ansible-galaxy collection install -r requirements.yml
```

### Azure authentication

The playbook authenticates to Azure using environment variables. These should be set in Semaphore as an environment or injected via a vault:

| Variable | Description |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID |
| `AZURE_CLIENT_ID` | Service principal client ID |
| `AZURE_SECRET` | Service principal secret |
| `AZURE_TENANT` | Azure tenant ID |

The service principal used must have sufficient permissions to create managed identities and assign RBAC roles in the target subscription.

## Variables

| Variable | Required | Description | Example |
|---|---|---|---|
| `subscription_id` | Yes | Azure subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `resource_group` | Yes | Resource group — must follow `rg-mp-<mission-plane-name>-umi` | `rg-mp-avd-umi` |
| `location` | Yes | Azure region | `uksouth` |
| `env` | Yes | Environment label (lowercase) | `prod` |
| `purpose` | Yes | Purpose label (lowercase) | `avd` |
| `assignment_scope` | No | Scope for role assignments, defaults to subscription scope | `/subscriptions/{{ subscription_id }}` |

## Running via Semaphore

1. **Add this repository** as a Git repository in Semaphore.
2. **Create an environment** in Semaphore containing the four `AZURE_*` variables above.
3. **Create a task template** with:
   - Repository: this repo
   - Playbook: `create_umi.yml`
   - Environment: the environment created above
4. **Add extra variables** for each run (or set defaults in the template):
   ```
   subscription_id=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   resource_group=rg-mp-avd-umi
   location=uksouth
   env=prod
   purpose=avd
   ```
5. **Run the task.** Semaphore will pull the latest playbook from Git and execute it.

## Running manually

```bash
ansible-playbook create_umi.yml \
  -e subscription_id=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  -e resource_group=rg-mp-avd-umi \
  -e location=uksouth \
  -e env=prod \
  -e purpose=avd
```

## Notes

- The playbook is idempotent — re-running it will not duplicate the UMI or role assignments.
- Custom `MS-ISR:` roles must already exist in the target subscription. If a role is not found the playbook will warn and continue rather than fail.
- A summary of the created UMI and assigned roles is printed at the end of each run.
