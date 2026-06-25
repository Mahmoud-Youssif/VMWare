# Execution Environment — ee-vmware

Custom Ansible Execution Environment for VMware provisioning on AAP 2.5.

## Contents

| File | Purpose |
|------|---------|
| `execution-environment.yml` | EE build definition (ansible-builder v3) |
| `requirements.yml` | Ansible Galaxy collections |
| `requirements.txt` | Python pip packages |
| `bindep.txt` | System (RPM) packages |

## Included Collections

| Collection | Use |
|------------|-----|
| `vmware.vmware_rest` | VM provisioning via vCenter REST API |
| `community.vmware` | VM clone/customisation via legacy SOAP API |
| `cloud.vmware_ops` | High-level VM provisioning role |
| `ansible.windows` | Windows configuration (WinRM) |

## Prerequisites

```bash
pip install ansible-builder>=3.0 ansible-navigator
```

You must be logged in to `registry.redhat.io`:

```bash
podman login registry.redhat.io
```

## Build

```bash
cd EE_vmware

ansible-builder build \
  --file execution-environment.yml \
  --tag ee-vmware:latest \
  --verbosity 3
```

To build with a specific version tag:

```bash
ansible-builder build \
  --file execution-environment.yml \
  --tag ee-vmware:1.0.0 \
  --verbosity 3
```

## Push to a Private Registry

```bash
podman tag ee-vmware:latest <your-registry>/ee-vmware:latest
podman push <your-registry>/ee-vmware:latest
```

## Test Locally with ansible-navigator

```bash
cd ..   # project root

ansible-navigator run playbook.yml \
  --execution-environment-image ee-vmware:latest \
  --mode stdout \
  --pull-policy missing
```

## Use in AAP

1. Push the image to a registry accessible from AAP.
2. In AAP → **Execution Environments** → **Add**:
   - **Name:** `ee-vmware`
   - **Image:** `<your-registry>/ee-vmware:latest`
   - **Pull:** Always
3. Assign the EE to your VMware Job Templates.

## Rebuild Triggers

Rebuild this EE whenever:
- A new AAP 2.5 base image is released
- A collection version is bumped in `requirements.yml`
- A new Python dependency is added to `requirements.txt`
