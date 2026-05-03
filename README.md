# Netwrix Directory Manager – Ansible Automation

Ansible playbooks for managing groups and users via the **Netwrix Directory Manager (NDM) REST API**, designed to run on **Ansible Automation Platform (AAP)**.

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
│       └── vault.yml           # Encrypted credentials template
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
| NDM version | 11.x (GroupIDDataService REST API) |
| Service account | NDM account with API access rights |
| NDM Identity Store ID | Found under **Admin Center → Identity Stores** |

---

## Configuration

### 1. Connection settings (`group_vars/all/vars.yml`)

```yaml
ndm_host: "netwrix-dm.example.com"
ndm_port: 4443
ndm_validate_certs: true
ndm_identity_store_id: "1"
ndm_default_group_container: "OU=Groups,DC=example,DC=com"
ndm_default_user_container:  "OU=Users,DC=example,DC=com"
```

### 2. Credentials

Store credentials in Ansible Vault or as an AAP Custom Credential:

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

`vault.yml` content:
```yaml
ndm_username: "svc_ansible@example.com"
ndm_password: "ChangeMe!"
```

In AAP, create a **Custom Credential Type** with these injector fields and attach it to each Job Template.

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

## Usage

### Group Management

#### Create a group
```bash
ansible-playbook playbooks/group_create.yml \
  -e "ndm_host=netwrix-dm.example.com" \
  -e "ndm_username=svc_ansible@example.com" \
  -e "ndm_password=secret" \
  -e "ndm_identity_store_id=1" \
  -e "group_name=GRP-AppTeam" \
  -e "group_container='OU=Groups,DC=example,DC=com'" \
  -e "group_description='Application team group'" \
  -e '{"group_owners":["CN=jdoe,OU=Users,DC=example,DC=com"]}'
```

#### Delete a group
```bash
ansible-playbook playbooks/group_delete.yml \
  -e "group_identity=GRP-AppTeam"
```

#### Add members to a group
```bash
ansible-playbook playbooks/group_add_members.yml \
  -e "group_identity=GRP-AppTeam" \
  -e '{"group_members":["CN=jdoe,OU=Users,DC=example,DC=com","CN=jsmith,OU=Users,DC=example,DC=com"]}'
```

#### Remove members from a group
```bash
ansible-playbook playbooks/group_remove_members.yml \
  -e "group_identity=GRP-AppTeam" \
  -e '{"group_members":["CN=jdoe,OU=Users,DC=example,DC=com"]}'
```

#### Assign owners to a group
```bash
ansible-playbook playbooks/group_set_owners.yml \
  -e "group_identity=GRP-AppTeam" \
  -e '{"group_owners":["CN=manager,OU=Users,DC=example,DC=com"]}'
```

### User Management

#### Create a user
```bash
ansible-playbook playbooks/user_create.yml \
  -e "user_first_name=John" \
  -e "user_last_name=Doe" \
  -e "user_sam_account_name=jdoe" \
  -e "user_principal_name=jdoe@example.com" \
  -e "user_password=P@ssw0rd123!" \
  -e "user_container='OU=Users,DC=example,DC=com'"
```

#### Delete a user
```bash
ansible-playbook playbooks/user_delete.yml \
  -e "user_identity=jdoe"
```

---

## AAP Job Template Setup

1. **Source Control** – point to this repository, branch `claude/netwrix-api-integration-8pZ1w`
2. **Playbook** – select the desired playbook from the `playbooks/` directory
3. **Credentials** – attach Vault credential (or Custom Credential with `ndm_username`/`ndm_password`)
4. **Survey** – create survey questions for required extra-vars (e.g. `group_name`, `group_identity`, `group_members`, `ndm_host`, `ndm_identity_store_id`)
5. **Variables** – set `ndm_host`, `ndm_port`, `ndm_validate_certs`, `ndm_identity_store_id` as job template variables

### Recommended AAP Custom Credential Type

**Input configuration (YAML):**
```yaml
fields:
  - id: ndm_username
    type: string
    label: NDM Username
  - id: ndm_password
    type: string
    label: NDM Password
    secret: true
  - id: ndm_host
    type: string
    label: NDM Host
  - id: ndm_identity_store_id
    type: string
    label: Identity Store ID
required:
  - ndm_username
  - ndm_password
  - ndm_host
  - ndm_identity_store_id
```

**Injector configuration (YAML):**
```yaml
extra_vars:
  ndm_username: '{{ ndm_username }}'
  ndm_password: '{{ ndm_password }}'
  ndm_host: '{{ ndm_host }}'
  ndm_identity_store_id: '{{ ndm_identity_store_id }}'
```

---

## Notes

- `group_identity` and `user_identity` accept either a full **Distinguished Name (DN)** or **sAMAccountName**. NDM URL-encodes these internally; the playbooks apply `urlencode` for safety.
- `group_members` and `group_owners` are **lists of DNs**.
- `group_set_owners` **replaces** the entire owner list. To add a single owner without removing others, retrieve current owners first and append to the list.
- Passwords are protected with `no_log: true` throughout.
- Set `ndm_validate_certs: false` only in lab environments with self-signed certificates.
