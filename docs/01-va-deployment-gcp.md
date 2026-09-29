# Deploying a SailPoint Virtual Appliance on Google Cloud

> Lab write-up · SailPoint Human Fabric (formerly Identity Security Cloud / IdentityNow)
> Author: Karimunnisa-s · Date: 22 September 2026

## Goal

Stand up a SailPoint virtual appliance (VA) and pair it to a tenant cluster, so that
on-premises-style sources (Active Directory, JDBC) can be reached from the tenant.
Constraint: my only machine is an Apple Silicon MacBook Pro (M2 Pro).

## Why not run it locally

The VA image ships as an OVF bundle (`.ovf`, `.mf`, `.vmdk`) built for x86-64, and
SailPoint's requirements state the hypervisor must expose x86 instructions to the VA
(minimum instruction level Intel Nehalem / AMD Opteron Gen 4).

VirtualBox installs on Apple Silicon but runs only ARM guests, so the appliance cannot
boot there. Emulating x86 (UTM/QEMU) is technically possible but far too slow for a
4 vCPU / 16 GB appliance running connector services.

**Decision:** run the appliance in Google Cloud and import the `.vmdk` as a custom image.
Local alternative, if an x86 machine is available: VirtualBox / VMware / Hyper-V on
Windows or Linux with at least 32 GB RAM.

## What I built

```
Virtual appliance  ── outbound HTTPS 443 ──►  SailPoint tenant (SaaS)
(GCP, us-central1)
        │
        └─► reaches sources that are not internet-facing (AD, JDBC)
```

No inbound connection from SailPoint is required: the appliance dials out and holds the
connection open. That is what makes a cloud-hosted appliance behind a closed firewall a
valid deployment.

| Component | Value |
|---|---|
| Cloud | Google Cloud (free trial credit) |
| Machine type | `e2-standard-4` — 4 vCPU, 16 GB RAM (SailPoint minimum) |
| Boot disk | Custom image from the VA `.vmdk`, balanced PD, 128 GB |
| Region / zone | `us-central1` |
| Ingress | SSH (22) restricted to my home IP `/32` |
| Egress | 443 (tenant + updates), 53 (DNS), 123 (NTP) |
| Cluster | `SailPoint VA` — an existing tenant cluster; this appliance was added as a member |

<img width="1510" height="897" alt="va-connected" src="https://github.com/user-attachments/assets/b2f60d61-3b4d-4562-a7bc-7681f4ae9262" />

  

*The GCP appliance (10.128.0.2) reporting **Connected** with CCG version 1320. Two earlier
appliances in the same cluster show Inactive.*

## Steps

1. **Download and extract** the VA package; keep the `.vmdk` (the disk). The `.ovf`
   (VM settings) and `.mf` (checksums) are not needed for a cloud import.
2. **Create a GCP project**, set a billing budget alert, and enable the
   Compute Engine and VM Migration APIs.
3. **Upload** the `.vmdk` to a Cloud Storage bucket.
4. **Import** it as a custom image with Migrate to Virtual Machines:

   ```bash
   gcloud compute migration image-imports create sailpoint-va-disk \
     --source-file=gs://BUCKET/sailpoint-va.vmdk \
     --location=us-central1 --skip-os-adaptation
   ```

   `--skip-os-adaptation` keeps the appliance's OS untouched — it is a vendor image,
   not a general-purpose Linux VM to be adapted for GCP.
5. **Create the VM** from that custom image: `e2-standard-4`, 128 GB boot disk.
6. **Restrict SSH** in the `default-allow-ssh` firewall rule to my own public IP `/32`.
7. **Pair the VA** to the tenant cluster:

   ```bash
   va-bootstrap set-passphrase -t demo   # demo tenant: *.identitynow-demo.com
   va-bootstrap pair          # prints a pairing code
   ```

   Enter the code in the tenant under **Admin → Connections → Virtual Appliances →
   <cluster> → Edit → Virtual Appliances → Add New → VA**, then wait ~30 minutes for
   configuration to complete.

Static IP configuration from SailPoint's docs is not required here: GCP keeps the VM's
internal IP across restarts.

## Problems and fixes

| Symptom | Root cause | Fix |
|---|---|---|
| VA image won't run on my laptop | Apple Silicon (ARM) host; VA is x86-64 only | Moved the deployment to GCP |
| `FAILED_PRECONDITION: TargetProject ... not found` on image import | The project was never registered as a target in Migrate to Virtual Machines, and its service agent had no rights to the bucket | Added the project under **Migrate to VMs → Targets**; created the service identity and granted it `roles/storage.objectViewer` on the bucket and `roles/vmmigration.serviceAgent` on the project |
| `n2-standard-4 ... currently unavailable in us-central1-a` | Transient capacity shortage in that zone | Switched to `e2-standard-4` (same 4 vCPU / 16 GB, better availability) |
| `VA is already configured as a prod tenant, cannot use internal as tenant type` | The VA bootstrapped against the production endpoint, but the tenant is a demo tenant (`*.identitynow-demo.com`) | `va-bootstrap reset`, then `set-passphrase -t demo` to match the demo tenant |
| Pairing code always identical and rejected as "expired or not found" | The stale code had been minted against the wrong endpoint, so the tenant could never resolve it — re-running `pair` returned the cached code rather than a new one | The reset above cleared the local bootstrap state; the next `pair` produced a fresh, valid code |

## What I learned

- **The appliance is a network bridge, not a data store.** It only needs outbound 443 to
  the tenant; nothing inbound from SailPoint. That is what makes a cloud-hosted VA with a
  locked-down firewall a legitimate deployment rather than a shortcut.
- **"Expired" can mean "issued against the wrong endpoint."** Repeating the failing action
  was never going to help; the identical code each run was the signal that state was
  cached locally and had to be cleared.
- **Sizing is not negotiable.** Halving the VM to 2 vCPU / 8 GB would likely surface later
  as connector services that never finish deploying — a failure mode easily mistaken for a
  configuration error.
- **Capacity errors are re-evaluated on every start**, so a VM that starts today may not
  start tomorrow. Machine family choice is an availability decision, not just a cost one.

## Interview talking point

> "I deployed a SailPoint VA on GCP because my laptop is ARM-based and the appliance is
> x86-only. The interesting part was the pairing failure: the code was rejected as expired,
> but re-running the command kept returning the *same* code, which told me the state was
> cached locally from a bootstrap against the wrong tenant type. Resetting the bootstrap and
> re-running it with the correct type produced a valid code and the VA paired."

## Guardrails

- **Access:** inbound SSH (22) is limited to my own public address; nothing else is exposed.
- **Cost:** a $50 budget alert is set, the VM is stopped when not in use (only disk storage
  bills while stopped), and the VM, custom image, bucket and disks are deleted when the lab
  ends.

## Not published here

Tenant name and URL, cluster passphrase, pairing codes, the VM's external IP, the GCP
project ID, and any screenshot showing them. The only tenant detail here is the generic
demo-tenant suffix, which is what made the `-t demo` flag necessary.
