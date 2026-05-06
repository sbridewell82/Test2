# Netwrix Directory Manager – Ansible Automation

Ansible playbooks for managing groups and users via the **Netwrix Directory Manager (NDM) REST API**, designed to run with **Ansible Semaphore** backed by this Git repository.

---

## Project Structure

```
.
├── ansible.cfg
├── inventory/
│   └── hosts.yml               # localhost (all API calls run locally)
├── group_vars/
│   └── all/
│       ├── vars.yml            # Default connection settings
│       └── vault.yml           # Ansible Vault encrypted credentials
├── roles/
│   └── netwrix_dm/
│       ├── defaults/main.yml   # All configurable defaults
│       ├── meta/main.yml
│       └── tasks/
│           ├── main.yml            # Entry point – authenticates then delegates
│           ├── authenticate.yml    # Fetches OAuth2 bearer token
│           ├── group_create.yml
│           ├── group_delete.yml
│           ├── group_add_members.yml
│           ├── group_remove_members.yml
│           ├── group_set_owners.yml
│           ├── user_create.yml
│           └── user_delete.yml
└── playbooks/
    ├── group_create.yml
    ├── group_delete.yml
    ├── group_add_members.yml
    ├── group_remove_members.yml
    ├── group_set_owners.yml
    ├── user_create.yml
    └── user_delete.yml
```

---

## Prerequisites

| Requirement | Detail |
|---|---|
| Ansible | 2.12 or later |
| Ansible Semaphore | Any recent version with Git repository support |
| NDM version | 11.x (GroupIDDataService REST API) |
| Service account | NDM account with API access rights |
| NDM Identity Store ID | Found under **Admin Center → Identity Stores** |

---

## Configuration

### 1. Connection settings (`group_vars/all/vars.yml`)

```yaml
ndm_host: "myid.lmc-aero-up.com"
ndm_port: 4443
ndm_validate_certs: true
ndm_identity_store_id: "1"
ndm_default_group_container: "OU=Groups,DC=lmc-aero-up,DC=com"
ndm_default_user_container:  "OU=Users,DC=lmc-aero-up,DC=com"
```

### 2. Credentials (Ansible Vault)

NDM credentials are stored encrypted in `group_vars/all/vault.yml`. Encrypt it before committing:

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

`vault.yml` plaintext content:
```yaml
ndm_username: "svc_ansible@lmc-aero-up.com"
ndm_password: "ChangeMe!"
```

The vault password is stored in Semaphore's **Key Store** and supplied automatically at run time (see Semaphore Setup below).

---

## API Endpoints Used

| Operation | Method | Endpoint |
|---|---|---|
| Get token | POST | `/GroupIDSecurityService/connect/token` |
| Create group | POST | `/GroupIDDataService/api/IdentityStores/{id}/Groups` |
| Delete group | DELETE | `/GroupIDDataService/api/IdentityStores/{id}/Groups/{identity}` |
| Add members | POST | `/GroupIDDataService/api/IdentityStores/{id}/Groups/{identity}/Members` |
| Remove member | DELETE | `/GroupIDDataService/api/IdentityStores/{id}/Groups/{identity}/Members/{memberIdentity}` |
| Set owners | PATCH | `/GroupIDDataService/api/IdentityStores/{id}/Groups/{identity}` |
| Create user | POST | `/GroupIDDataService/api/IdentityStores/{id}/Users` |
| Delete user | DELETE | `/GroupIDDataService/api/IdentityStores/{id}/Users/{identity}` |

---

## Usage (CLI)

### Group Management

#### Create a group
```bash
ansible-playbook playbooks/group_create.yml \
  --vault-password-file ~/.vault_pass \
  -e "group_name=GRP-AppTeam" \
  -e "group_container='OU=Groups,DC=lmc-aero-up,DC=com'" \
  -e "group_description='Application team group'" \
  -e '{"group_owners":["CN=jdoe,OU=Users,DC=lmc-aero-up,DC=com"]}'
```

#### Delete a group
```bash
ansible-playbook playbooks/group_delete.yml \
  --vault-password-file ~/.vault_pass \
  -e "group_identity=GRP-AppTeam"
```

#### Add members to a group
```bash
ansible-playbook playbooks/group_add_members.yml \
  --vault-password-file ~/.vault_pass \
  -e "group_identity=GRP-AppTeam" \
  -e '{"group_members":["CN=jdoe,OU=Users,DC=lmc-aero-up,DC=com","CN=jsmith,OU=Users,DC=lmc-aero-up,DC=com"]}'
```

#### Remove members from a group
```bash
ansible-playbook playbooks/group_remove_members.yml \
  --vault-password-file ~/.vault_pass \
  -e "group_identity=GRP-AppTeam" \
  -e '{"group_members":["CN=jdoe,OU=Users,DC=lmc-aero-up,DC=com"]}'
```

#### Assign owners to a group
```bash
ansible-playbook playbooks/group_set_owners.yml \
  --vault-password-file ~/.vault_pass \
  -e "group_identity=GRP-AppTeam" \
  -e '{"group_owners":["CN=manager,OU=Users,DC=lmc-aero-up,DC=com"]}'
```

### User Management

#### Create a user
```bash
ansible-playbook playbooks/user_create.yml \
  --vault-password-file ~/.vault_pass \
  -e "user_first_name=John" \
  -e "user_last_name=Doe" \
  -e "user_sam_account_name=jdoe" \
  -e "user_principal_name=jdoe@lmc-aero-up.com" \
  -e "user_password=P@ssw0rd123!" \
  -e "user_container='OU=Users,DC=lmc-aero-up,DC=com'"
```

#### Delete a user
```bash
ansible-playbook playbooks/user_delete.yml \
  --vault-password-file ~/.vault_pass \
  -e "user_identity=jdoe"
```

---

## Semaphore Setup

### 1. Key Store

Create two entries in **Key Store**:

| Name | Type | Purpose |
|---|---|---|
| `git-repo-key` | SSH key or HTTP login | Access to this Git repository |
| `vault-password` | Login (password field only) | Ansible Vault decryption password |

For `vault-password`, set the **Password** field to your vault password and leave Username blank. Semaphore will pass this to `ansible-playbook --vault-password-file` automatically.

### 2. Repository

Add this Git repository under **Repositories**:

| Field | Value |
|---|---|
| Name | `netwrix-dm-ansible` |
| URL | `<this repo's Git URL>` |
| Branch | `claude/netwrix-api-integration-8pZ1w` |
| Access Key | `git-repo-key` |

### 3. Inventory

Create an inventory under **Inventory**:

| Field | Value |
|---|---|
| Name | `localhost` |
| Type | `Static` |
| Content | `localhost ansible_connection=local` |

### 4. Environment

Create an environment under **Environment** (optional – only needed for overrides):

```json
{
  "ndm_identity_store_id": "1"
}
```

Non-sensitive connection settings (`ndm_host`, `ndm_port`, `ndm_validate_certs`) are already set in `group_vars/all/vars.yml` and do not need to be repeated here.

### 5. Task Templates

Create one template per operation. Common settings for all templates:

| Field | Value |
|---|---|
| Repository | `netwrix-dm-ansible` |
| Inventory | `localhost` |
| Vault Password | `vault-password` (from Key Store) |
| Environment | *(environment created above)* |

| Template Name | Playbook |
|---|---|
| NDM – Create Group | `playbooks/group_create.yml` |
| NDM – Delete Group | `playbooks/group_delete.yml` |
| NDM – Add Group Members | `playbooks/group_add_members.yml` |
| NDM – Remove Group Members | `playbooks/group_remove_members.yml` |
| NDM – Set Group Owners | `playbooks/group_set_owners.yml` |
| NDM – Create User | `playbooks/user_create.yml` |
| NDM – Delete User | `playbooks/user_delete.yml` |

### 6. Template Surveys (Extra Variables per run)

Enable **"Allow extra variables"** on each template and prompt for the relevant vars at run time:

| Template | Prompt for |
|---|---|
| Create Group | `group_name`, `group_container`, `group_description`, `group_owners` |
| Delete Group | `group_identity` |
| Add Members | `group_identity`, `group_members` |
| Remove Members | `group_identity`, `group_members` |
| Set Owners | `group_identity`, `group_owners` |
| Create User | `user_first_name`, `user_last_name`, `user_sam_account_name`, `user_principal_name`, `user_password`, `user_container` |
| Delete User | `user_identity` |

---

## Notes

- `group_identity` and `user_identity` accept either a full **Distinguished Name (DN)** or **sAMAccountName**.
- `group_members` and `group_owners` are **lists of DNs** — pass them as JSON in the extra variables field: `["CN=jdoe,OU=Users,DC=lmc-aero-up,DC=com"]`
- `group_set_owners` **replaces** the entire owner list. To add a single owner without removing others, retrieve current owners first and append to the list.
- Passwords are protected with `no_log: true` throughout.
- Set `ndm_validate_certs: false` only in lab environments with self-signed certificates.
