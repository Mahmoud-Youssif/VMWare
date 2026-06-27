# VMware Ansible Automation

Ansible playbooks and roles for provisioning and configuring **RHEL VMs** on VMware vCenter using **cloud-init** via the VMware guestinfo datasource (open-vm-tools).

---

## Table of Contents

- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Template Preparation (run once)](#template-preparation-run-once)
- [Environment Variables](#environment-variables)
- [Playbooks](#playbooks)
- [Role: vmware](#role-vmware)
- [Execution Environment (EE)](#execution-environment-ee)
- [AAP Survey Auto-population](#aap-survey-auto-population)
- [Secret Management](#secret-management)
- [CI / Linting](#ci--linting)

---

## How It Works

```
Clone VM (off)
      │
      ▼
Inject guestinfo.metadata    ← static IP, hostname, DNS (network-v2 format)
Inject guestinfo.userdata    ← user, SSH key, password (#cloud-config)
      │
      ▼
Power ON
      │
      ▼  open-vm-tools feeds guestinfo to cloud-init
cloud-init runs on first boot
      │
      ▼
VM ready: hostname set, IP configured, SSH key deployed, user created
      │
      ▼
Post-boot verification (cloud-init status, hostname, IP assertions)
```

> **Why guestinfo instead of VMware customization spec?**
> RHEL 8/9 ships with `open-vm-tools` (not legacy VMware Tools). The modern approach is cloud-init with the VMware datasource — it reads `guestinfo.metadata` and `guestinfo.userdata` properties set on the VM in vCenter, applying full OS configuration on first boot without needing the guest customization engine.

---

## Requirements

- Ansible >= 2.14
- Python >= 3.9
- Access to a VMware vCenter instance
- RHEL 8/9 template with cloud-init and open-vm-tools (see [Template Preparation](#template-preparation-run-once))

### Collections

Collections are managed through the EE image. For local development, install them directly:

```bash
ansible-galaxy collection install -r EE_vmware/requirements.yml
```

| Collection | Purpose |
|---|---|
| `community.vmware` | Clone VM, inject guestinfo, power control |
| `vmware.vmware_rest` | vCenter REST API (used by `new_vm_coll.yml`) |
| `ansible.windows` | Windows modules (legacy `new_vm_coll.yml`) |
| `microsoft.ad` | Active Directory membership (replaces removed `win_domain_membership`) |
| `cloud.vmware_ops` | High-level role via Automation Hub (`new_playbook.yml`, Automation Hub only) |

---

## Template Preparation (run once)

Before cloning, your RHEL template VM must have cloud-init configured to use the VMware datasource. Run these commands **once** on the template, then power it off and use it as the source:

```bash
# Install required packages
sudo dnf install -y open-vm-tools cloud-init

# Tell cloud-init to use the VMware guestinfo datasource
sudo bash -c 'echo "datasource_list: [VMware]" > /etc/cloud/cloud.cfg.d/99-vmware-datasource.cfg'

# (Optional) Disable cloud-init network management if using NM directly
# sudo bash -c 'echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg'

# Enable services
sudo systemctl enable open-vm-tools cloud-init cloud-init-local cloud-config cloud-final

# Clean cloud-init state before snapshot — IMPORTANT
sudo cloud-init clean --logs
sudo poweroff
```

Take a snapshot or export the powered-off VM as the template for all future clones.

---

## Environment Variables

All credentials are sourced from environment variables. Set the following before running any playbook:

```bash
# vCenter connection (used by all playbooks)
export VCENTER_HOST="vcenter.yourdomain.com"
export VCENTER_USER="administrator@vsphere.local"
export VCENTER_PASSWORD="your_vcenter_password"

# For the vmware role (playbook.yml)
export VMWARE_HOST="vcenter.yourdomain.com"
export VMWARE_USER="administrator@vsphere.local"
export VMWARE_PASSWORD="your_vcenter_password"

# New VM credentials (rhel_cloudinit_provision.yml / vmware role)
export VM_ADMIN_PASSWORD="secure_vm_password"
export VM_SSH_PUBLIC_KEY="ssh-rsa AAAAB3... user@host"

# For AAP survey auto-population (vcenter_survey_refresh.yml)
export AAP_HOST="aap.yourdomain.com"
export AAP_TOKEN="your_aap_oauth_token"
export AAP_JOB_TEMPLATE_ID="42"
```

Alternatively, use Ansible Vault (see [Secret Management](#secret-management)).

---

## Playbooks

### `rhel_cloudinit_provision.yml` — **Recommended** — RHEL VM via cloud-init

Full end-to-end RHEL VM provisioning using cloud-init guestinfo. Clones the template, injects hostname + static IP + user + SSH key via guestinfo properties, powers on, and verifies the result.

```bash
ansible-playbook rhel_cloudinit_provision.yml \
  -e "vm_name=rhel-server-01" \
  -e "vm_hostname=rhel-server-01" \
  -e "template_name=RHEL9-Template" \
  -e "datacenter=DC1" \
  -e "cluster=Cluster01" \
  -e "datastore=DS01" \
  -e "folder=/DC1/vm/Servers" \
  -e "nic_portgroup=VM_Network" \
  -e "nic_ip=192.168.1.100" \
  -e "nic_prefix=24" \
  -e "nic_gw=192.168.1.1" \
  -e "dns_servers=[\"192.168.1.10\",\"192.168.1.11\"]" \
  -e "dns_domain=corp.local" \
  -e "vm_admin_user=ansible" \
  -e "vm_network_interface=ens192"
```

**What this playbook configures via cloud-init on first boot:**

| Setting | Payload |
|---|---|
| Static IP, prefix, gateway, DNS | `guestinfo.metadata` (network-v2) |
| Hostname / FQDN | `guestinfo.metadata` + `guestinfo.userdata` |
| Admin user + sudo | `guestinfo.userdata` |
| SSH public key | `guestinfo.userdata` |
| User password | `guestinfo.userdata` (`chpasswd`) |

---

### `playbook.yml` — Clone RHEL VM using the `vmware` role

Thin wrapper that calls the `vmware` role. Role variables are passed as extra-vars or defined in `group_vars`.

```bash
ansible-playbook playbook.yml \
  -e "ha_datacenter=DC1" \
  -e "vmware_cluster_name=Cluster01" \
  -e "new_vm_name=rhel-server-02" \
  -e "new_hostname=rhel-server-02" \
  -e "template_name=RHEL9-Template" \
  -e "nic_ip=192.168.1.101" \
  -e "nic_prefix=24" \
  -e "nic_gw=192.168.1.1" \
  -e "nic_virt_group=VM_Network" \
  -e "dns_servers=[\"192.168.1.10\"]" \
  -e "vm_admin_user=ansible" \
  -e "vm_network_interface=ens192"
```

---

### `vcenter_survey_refresh.yml` — Populate AAP Survey from live vCenter data

Connects to vCenter, collects all provisioning-relevant data (datacenters, clusters, datastores, networks, templates, folders), then updates the target AAP Job Template survey dropdowns automatically.

```bash
ansible-playbook vcenter_survey_refresh.yml
```

**What it collects and maps to survey questions:**

| vCenter Query | Survey Question | Variable |
|---|---|---|
| All datacenters | Datacenter | `datacenter_name` |
| All clusters | Cluster | `cluster_name` |
| All datastores (VMFS/NFS/vSAN) | Datastore | `datastore_name` |
| All networks / port groups | Network / Port Group | `network_name` |
| All VM templates | VM Template | `template_name` |
| All VM folders | VM Folder | `vmware_new_vm_folder` |
| — | VM Name (free text) | `vm_name` |
| — | New Hostname (free text) | `new_hostname` |
| — | IP Address (free text) | `new_ip_address` |
| — | Prefix Length (free text) | `nic_prefix` |
| — | Default Gateway (free text) | `gateway` |
| — | Domain Name (free text) | `dns_domain` |

Run on a schedule (e.g. nightly) or as a pre-requisite job in an AAP workflow to keep survey choices current.

---

### `new_vm_coll.yml` — Windows VM lifecycle (vmware.vmware_rest + microsoft.ad)

Full end-to-end Windows VM provisioning: deploy from template → wait for WinRM → domain join → reboot.

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

---

### `new_playbook.yml` — Provision VM via cloud.vmware_ops (Automation Hub)

Uses the `cloud.vmware_ops.provision_vm` role. Requires the collection from **Red Hat Automation Hub** — not available on public Ansible Galaxy.

```bash
# Configure Automation Hub in ansible.cfg first, then:
ansible-playbook new_playbook.yml \
  -e "vcenter_datacenter=DC1" \
  -e "vcenter_cluster=Cluster01" \
  -e "vcenter_datastore=DS01" \
  -e "vm_name=RHEL-003"
```

---

## Role: `vmware`

Located at `roles/vmware/`. Clones a RHEL VM from a vCenter template and configures it via cloud-init guestinfo (hostname, static IP, admin user, SSH key).

### Variables (`roles/vmware/defaults/main.yml`)

| Variable | Default | Description |
|---|---|---|
| `ha_datacenter` | `""` | vCenter datacenter name |
| `vmware_cluster_name` | `""` | Target cluster |
| `vmware_new_vm_folder` | `""` | VM folder path (optional) |
| `new_vm_name` | `""` | Name for the new VM in vCenter |
| `new_hostname` | `""` | OS hostname to set via cloud-init |
| `template_name` | `""` | Source template name |
| `nic_virt_group` | `""` | Port group / vSwitch name |
| `nic_ip` | `""` | Static IP address |
| `nic_prefix` | `"24"` | CIDR prefix length |
| `nic_gw` | `""` | Default gateway |
| `dns_servers` | `[]` | List of DNS server IPs |
| `dns_domain` | `""` | DNS search domain (optional) |
| `vm_network_interface` | `"ens192"` | NIC name inside the guest (VMXNET3 default) |
| `vm_admin_user` | `"ansible"` | Admin user created by cloud-init |
| `vm_admin_password` | `""` | Password for the admin user |
| `vm_ssh_public_key` | `""` | SSH public key deployed to the admin user |
| `vm_ssh_key` | `""` | Local path to SSH private key (for Ansible connection) |
| `ssh_wait_timeout` | `300` | Seconds to wait for SSH after power-on |

### vCenter credentials (`roles/vmware/vars/main.yml`)

```yaml
vmware:
  host: "{{ lookup('env', 'VMWARE_HOST') }}"
  username: "{{ lookup('env', 'VMWARE_USER') }}"
  password: "{{ lookup('env', 'VMWARE_PASSWORD') }}"
```

---

## Execution Environment (EE)

A custom Execution Environment for AAP 2.5 is defined under `EE_vmware/`.

### Build and push

```bash
cd EE_vmware

# Log in to registries
podman login registry.redhat.io   # Red Hat base image
podman login quay.io              # push destination

# Build
ansible-builder build \
  --file execution-environment.yml \
  --tag quay.io/myoussif/ee-vmware:latest \
  --verbosity 3

# Push
podman push quay.io/myoussif/ee-vmware:latest
```

### What is bundled in the EE

| Layer | Contents |
|---|---|
| Base image | `registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel9:latest` |
| Collections | `community.vmware`, `vmware.vmware_rest`, `ansible.windows`, `microsoft.ad` |
| Python (3.12) | `pyvmomi`, `pywinrm`, `requests-ntlm` |
| System | `python3-pip` |

> Python packages are explicitly installed into `/usr/bin/python3.12` (the Python used by ansible-core) to avoid the RHEL9 Python 3.9 / 3.12 path split.

---

## AAP Survey Auto-population

Use `vcenter_survey_refresh.yml` in an **AAP Workflow** as the first job before the provisioning job template. This keeps survey dropdowns (datacenter, cluster, datastore, template, network) up to date with live vCenter inventory.

**Recommended workflow:**

```
[vcenter_survey_refresh] → [rhel_cloudinit_provision / playbook.yml]
```

Required credentials in AAP:
- **VMware vCenter** credential (maps to `VCENTER_HOST`, `VCENTER_USER`, `VCENTER_PASSWORD`)
- **Machine** credential (SSH key or password for the new VM)
- **Custom** credential for `VM_ADMIN_PASSWORD` and `VM_SSH_PUBLIC_KEY`

---

## Secret Management

Use Ansible Vault to encrypt sensitive values locally:

```bash
# Copy the example and fill in real values
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Encrypt
ansible-vault encrypt group_vars/all/vault.yml

# Run playbooks with vault
ansible-playbook rhel_cloudinit_provision.yml --ask-vault-pass
```

> In AAP, secrets are managed via **Credentials** — vault files are not needed.

---

## CI / Linting

This project runs **both** a GitHub Actions workflow and a GitLab CI pipeline:

| File | Platform | Active? |
|---|---|---|
| `.github/workflows/ci.yml` | GitHub Actions | Yes — every push/PR to `main` |
| `.gitlab-ci.yml` | GitLab CI | Kept for future GitLab mirror/move |

### GitHub Actions jobs

| Job | Stage | What it checks |
|---|---|---|
| `yamllint` | lint | YAML formatting (config: `.yamllint.yml`) |
| `ansible-lint` | lint | Ansible best practices (config: `.ansible-lint`) |
| `syntax-check` | validate | Syntax for all playbooks |
| `ee-build` | build | Builds and pushes `ee-vmware` to `quay.io/myoussif/ee-vmware` (EE changes only) |

### Required GitHub Secrets

Set under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `RHN_USERNAME` | Red Hat registry username |
| `RHN_PASSWORD` | Red Hat registry password |
| `QUAY_USERNAME` | `myoussif` |
| `QUAY_PASSWORD` | quay.io password or robot account token |

### Run linting locally

```bash
pip install ansible-lint yamllint
yamllint .
ansible-lint
```
