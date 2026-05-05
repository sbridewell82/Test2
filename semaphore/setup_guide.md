# Semaphore Setup Guide — CTERA Share Creation

## One-time project setup

### 1. Key Store — store the CTERA password as a secret

1. Go to **Key Store** → **New Key**
2. **Type**: `Secret`
3. **Name**: `ctera-edge-password`
4. **Secret**: your CTERA admin password
5. Save

### 2. Environment — expose the secret as an environment variable

1. Go to **Environment** → **New Environment**
2. **Name**: `CTERA Edge`
3. Paste the following JSON, referencing the key you just created:

```json
{
  "ENV": {
    "CTERA_PASSWORD": "$ctera-edge-password"
  }
}
```

4. Update `playbooks/create_share.yml` to read the password from the environment if you prefer that approach, or pass it directly via extra vars referencing `"{{ lookup('env', 'CTERA_PASSWORD') }}"`.

### 3. Inventory

1. Go to **Inventory** → **New Inventory**
2. **Name**: `localhost`
3. **Type**: `Static`
4. Paste contents of `inventory/hosts.yml`

### 4. Repository

1. Go to **Repositories** → **New Repository**
2. Point it at this repo and the `claude/ctera-api-create-shares-fv3Av` branch (or `main` once merged)

### 5. Task Template

1. Go to **Task Templates** → **New Template**
2. Fill in:

| Field | Value |
|---|---|
| **Name** | `Create CTERA Share` |
| **Playbook** | `playbooks/create_share.yml` |
| **Inventory** | `localhost` (created above) |
| **Repository** | your repo (created above) |
| **Environment** | `CTERA Edge` (created above) |

3. In **Extra Variables**, paste the contents of `semaphore/extra_vars_example.yml`
4. Save

---

## Running a task

1. Open the `Create CTERA Share` template
2. Click **Run**
3. In the **Advanced** section you can override any variable for this run:
   - `share_name` — name of the new share
   - `share_directory` — path on the CTERA Edge device
   - `share_comment` — description shown to users
   - `share_protocols` — list: `smb`, `nfs`, `afp`, `ftp`, `rsync`, `pc_agent`
   - `share_acl` — list of `{principal_type, name, access}` entries (see below)
   - `ctera_host` — Edge device IP/hostname (if different from the default)

### ACL entry format

```yaml
share_acl:
  - principal_type: "DG"   # DG=domain group, DU=domain user, LG=local group, LU=local user
    name: "CORP\\GroupName"
    access: "RW"           # RW=read-write, RO=read-only, NA=no access
```

### Protocol options

| Value | Protocol |
|---|---|
| `smb` | Windows File Sharing (CIFS/SMB) — enabled by default |
| `nfs` | NFS |
| `afp` | Apple Filing Protocol |
| `ftp` | FTP |
| `rsync` | RSYNC |
| `pc_agent` | CTERA Backup Agent destination |
