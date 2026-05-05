# Semaphore Setup Guide — Dell PowerScale (OneFS) Share Creation

## One-time project setup

### 1. Key Store — store the cluster password as a secret

1. Go to **Key Store** → **New Key**
2. **Type**: `Secret`
3. **Name**: `onefs-password`
4. **Secret**: your OneFS admin password
5. Save

### 2. Environment — expose the secret as an environment variable

1. Go to **Environment** → **New Environment**
2. **Name**: `PowerScale Cluster`
3. Paste the following JSON, referencing the key you just created:

```json
{
  "ENV": {
    "ONEFS_PASSWORD": "$onefs-password"
  }
}
```

4. In `playbooks/create_share_onefs.yml`, `onefs_password` is read from the extra-variable
   supplied at run time. To pull it from the environment instead, add this task before the
   main task:

```yaml
- name: Read password from environment
  ansible.builtin.set_fact:
    onefs_password: "{{ lookup('env', 'ONEFS_PASSWORD') }}"
```

### 3. Inventory

1. Go to **Inventory** → **New Inventory**
2. **Name**: `localhost`
3. **Type**: `Static`
4. Paste the contents of `inventory/hosts.yml`

### 4. Repository

1. Go to **Repositories** → **New Repository**
2. Point it at this repo and the `claude/onefs-integration-BvED3` branch (or `main` once merged)

### 5. Task Template

1. Go to **Task Templates** → **New Template**
2. Fill in:

| Field | Value |
|---|---|
| **Name** | `Create PowerScale Share` |
| **Playbook** | `playbooks/create_share_onefs.yml` |
| **Inventory** | `localhost` (created above) |
| **Repository** | your repo (created above) |
| **Environment** | `PowerScale Cluster` (created above) |

3. In **Extra Variables**, paste the contents of `semaphore/extra_vars_example_onefs.yml`
4. Save

---

## Running a task

1. Open the `Create PowerScale Share` template
2. Click **Run**
3. In the **Advanced** section you can override any variable for this run:

| Variable | Description |
|---|---|
| `share_type` | `smb`, `nfs`, or `both` |
| `share_name` | SMB share name (required for smb/both) |
| `share_path` | Path on the cluster, e.g. `/ifs/finance` |
| `share_description` | Optional description |
| `onefs_zone` | Access zone (default `System`) |
| `share_permissions` | SMB permission list (see below) |
| `nfs_rw_clients` | List of hosts/networks with read-write NFS access |
| `nfs_root_clients` | List of hosts exempt from root squash |
| `onefs_host` | Cluster hostname / SmartConnect name |

---

## SMB permission entry format

```yaml
share_permissions:
  - name: "CORP\\GroupName"    # domain group
    type: "group"              # user | group | wellknown
    permission: "full"         # full | change | read
    permission_type: "allow"   # allow | deny  (default: allow)
  - name: "Everyone"
    type: "wellknown"
    permission: "read"
```

## NFS client control format

```yaml
nfs_clients:       []                  # empty = all hosts may mount
nfs_rw_clients:    ["10.0.0.0/24"]    # CIDR notation or hostname
nfs_ro_clients:    []
nfs_root_clients:  ["10.0.0.5"]       # hosts exempt from root squash
nfs_all_dirs:      false               # allow sub-directory mounts
nfs_no_root_squash: false              # true = root maps to root (use with caution)
```

## Access zones

If you have multiple access zones configured on the cluster, set `onefs_zone` to the
target zone name. Shares and exports created in a zone are only visible to clients
connected through that zone's IP pool.

```yaml
onefs_zone: "HR"   # or "Finance", "System" (default), etc.
```
