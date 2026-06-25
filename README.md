# VMware Ansible Automation

Ansible playbooks and roles for provisioning and configuring Windows VMs on VMware vCenter.

## Requirements

- Ansible >= 2.14
- Python >= 3.9
- Access to a VMware vCenter instance

### Install collections

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

Collections used:

| Collection | Purpose |
|------------|---------|
| `vmware.vmware_rest` | VM provisioning via vCenter REST API (`new_vm_coll.yml`) |
| `community.vmware` | VM clone/customization via legacy API (`playbook.yml`) |
| `cloud.vmware_ops` | High-level VM provisioning role (`new_playbook.yml`) |
| `ansible.windows` | Windows configuration (hostname, network, domain join) |

---

## Environment Variables

All credentials are sourced from environment variables. Set the following before running any playbook:

```bash
export VCENTER_HOST="vcenter.yourdomain.com"
export VCENTER_USER="administrator@vsphere.local"
export VCENTER_PASSWORD="your_vcenter_password"

# For Windows guest configuration (new_vm_coll.yml)
export GUEST_PASSWORD="local_admin_password"
export DOMAIN_ADMIN_USER="domain_admin@yourdomain.com"
export DOMAIN_ADMIN_PASSWORD="domain_admin_password"

# For the vmware role (playbook.yml)
export VMWARE_HOST="vcenter.yourdomain.com"
export VMWARE_USER="administrator@vsphere.local"
export VMWARE_PASSWORD="your_vcenter_password"
```

Alternatively, use Ansible Vault (see [Secret Management](#secret-management)).

---

## Playbooks

### `playbook.yml` — Clone Windows VM (community.vmware role)

Uses the `vmware` role to clone a Windows VM from a template using the `community.vmware.vmware_guest` module.

```bash
ansible-playbook playbook.yml \
  -e "ha_datacenter=DC1" \
  -e "vmware_cluster_name=Cluster01" \
  -e "new_vm_name=WinVM-001" \
  -e "template_name=Win2022-Template" \
  -e "nic_ip=192.168.1.50" \
  -e "nic_netmask=255.255.255.0" \
  -e "nic_gw=192.168.1.1" \
  -e "nic_virt_group=VM_Network" \
  -e "win_domain=corp.local" \
  -e "new_vm_password=SecurePass123!" \
  -e "ad_admin=admin@corp.local" \
  -e "ad_admin_pass=AdminPass123!"
```

### `new_vm_coll.yml` — Full Windows VM lifecycle (vmware.vmware_rest)

Full end-to-end provisioning: deploy from template → wait for WinRM → configure network → domain join → reboot.

```bash
ansible-playbook new_vm_coll.yml \
  -e "vm_name=WinVM-002" \
  -e "template_name=Win2022-Template" \
  -e "datacenter_name=DC1" \
  -e "cluster_name=Cluster01" \
  -e "datastore_name=DS01" \
  -e "new_hostname=WINVM002" \
  -e "new_ip_address=192.168.1.51" \
  -e "domain_name=corp.local"
```

### `vcenter_survey_refresh.yml` — Populate AAP Survey from live vCenter data

Connects to vCenter, collects all provisioning-relevant data (datacenters, clusters, datastores, networks, VM templates, folders), then updates the target AAP Job Template survey dropdowns automatically.

**Required environment variables:**

```bash
export VCENTER_HOST="vcenter.yourdomain.com"
export VCENTER_USER="administrator@vsphere.local"
export VCENTER_PASSWORD="your_vcenter_password"
export AAP_HOST="aap.yourdomain.com"
export AAP_TOKEN="your_aap_oauth_token"       # or use AAP_USER + AAP_PASSWORD
export AAP_JOB_TEMPLATE_ID="42"              # ID of the provisioning Job Template
```

```bash
ansible-playbook vcenter_survey_refresh.yml
```

**What it collects and maps to survey questions:**

| vCenter Query | Survey Question | Variable |
|--------------|----------------|----------|
| All datacenters | Datacenter | `datacenter_name` |
| All clusters | Cluster | `cluster_name` |
| All datastores (VMFS/NFS/vSAN) | Datastore | `datastore_name` |
| All networks / port groups | Network / Port Group | `network_name` |
| All VM templates | VM Template | `template_name` |
| All VM folders | VM Folder | `vmware_new_vm_folder` |
| — | VM Name (free text) | `vm_name` |
| — | New Hostname (free text) | `new_hostname` |
| — | IP Address (free text) | `new_ip_address` |
| — | Subnet Mask (free text) | `subnet_mask` |
| — | Default Gateway (free text) | `gateway` |
| — | Domain Name (free text) | `domain_name` |

Run this playbook on a schedule (e.g. nightly) or as a pre-requisite job in a workflow to keep survey choices current.

---

### `new_playbook.yml` — Provision VM (cloud.vmware_ops)

Example using the `cloud.vmware_ops.provision_vm` collection role. Accepts placement and hardware vars.

```bash
ansible-playbook new_playbook.yml \
  -e "vcenter_datacenter=DC1" \
  -e "vcenter_cluster=Cluster01" \
  -e "vcenter_datastore=DS01" \
  -e "vm_name=WinVM-003"
```

---

## Role: `vmware`

Located at `roles/vmware/`. Clones and customizes a Windows VM from a vCenter template.

### Key variables (`roles/vmware/defaults/main.yml`)

| Variable | Description |
|----------|-------------|
| `ha_datacenter` | vCenter datacenter name |
| `vmware_cluster_name` | Target cluster |
| `vmware_new_vm_folder` | VM folder path (optional) |
| `new_vm_name` | Name for the new VM |
| `template_name` | Source template name |
| `nic_virt_group` | Port group / vSwitch name |
| `nic_ip` | Static IP address |
| `nic_netmask` | Subnet mask |
| `nic_gw` | Default gateway |
| `win_domain` | Windows domain to join |
| `win_dns_servers` | List of DNS server IPs |
| `new_vm_password` | Local Administrator password |
| `ad_admin` | Domain admin account |
| `ad_admin_pass` | Domain admin password |

---

## Secret Management

Use Ansible Vault to encrypt sensitive values:

```bash
# Copy the example and fill in real values
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Encrypt the vault file
ansible-vault encrypt group_vars/all/vault.yml

# Run playbooks with vault
ansible-playbook playbook.yml --ask-vault-pass
```

---

## WinRM Setup

Before Ansible can manage a Windows VM, WinRM must be enabled. Use the included script on the target VM:

```powershell
# Run as Administrator on the Windows VM
powershell.exe -ExecutionPolicy Unrestricted -File .\Enable-WinRM-HTTP-HTTPS.ps1
```

For more details see the [Ansible Windows Setup documentation](https://docs.ansible.com/ansible/latest/user_guide/windows_setup.html).

---

## CI / Linting

This project uses GitLab CI (`.gitlab-ci.yml`) with three jobs:

| Job | Stage | What it checks |
|-----|-------|---------------|
| `yamllint` | lint | YAML formatting |
| `ansible-lint` | lint | Ansible best practices |
| `syntax-check` | validate | Playbook syntax |

Run linting locally:

```bash
pip install ansible-lint yamllint
yamllint .
ansible-lint
```
