# Ephemeral Linux kernel builders on EC2

OpenTofu config for throwaway Ubuntu LTS build boxes that:

- run the latest Ubuntu LTS (`ubuntu_version`, default 26.04), x86_64
- have the kernel build toolchain (`build-essential`, `flex`, `bison`, `libelf-dev`, `libssl-dev`, `dwarves`, ...)
- download the latest stable kernel from kernel.org to `~ubuntu/linux` (a symlink to `~ubuntu/linux-<version>`)
- have Rust installed via rustup for the `ubuntu` user
- have **no public IP**: they sit in a private subnet, with outbound traffic going through a NAT gateway and **no inbound security-group rules**
- join your tailnet on boot. You SSH in over Tailscale with your own key.

## Layout

| Dir         | Lifetime   | What                                                                                     |
|-------------|------------|------------------------------------------------------------------------------------------|
| `iam/`      | long-lived | EC2 runner IAM role + instance profile (SSM Session Manager, read the Tailscale key from SSM) |
| `network/`  | long-lived | VPC, public/private subnets, internet gateway, route tables, egress-only security group, SSH key pair |
| `instance/` | ephemeral  | NAT gateway + its Elastic IP and the private subnet's default route, instance(s)          |

Everything in `network/` is free while idle. Everything billable is in `instance/`, so after
`tofu -chdir=instance destroy` nothing is left costing money. `instance/` reads the network stack's
outputs from `network/terraform.tfstate`, so apply `network/` first.

## One-time setup

```fish
# 1. Log in to AWS
aws sso login --profile sandbox-admin

# 2. SSH key used to log in as `ubuntu`
ssh-keygen -t ed25519 -f ~/.ssh/kernel-builder -C kernel-builder

# 3. Tailscale auth key. In the admin console (Settings → Keys → Generate auth key),
#    check Reusable + Ephemeral (+ Pre-approved if device approval is on), then:
read -s -P 'Tailscale auth key: ' TS_KEY
aws ssm put-parameter --profile sandbox-admin --region us-west-2 \
    --name /kernel-builder/tailscale-auth-key --type SecureString \
    --value $TS_KEY --overwrite
set -e TS_KEY

# 4. IAM role / instance profile
tofu -chdir=iam init
tofu -chdir=iam apply

# 5. Long-lived network and SSH key pair
tofu -chdir=network init
tofu -chdir=network apply
```

When the Tailscale key expires (90 days max), generate a new one and run step 3 again.

## Bring up an instance

```fish
aws sso login --profile sandbox-admin     # if your session has expired
tofu -chdir=instance init                 # first time only
tofu -chdir=instance apply                # ~2 min, mostly creating the NAT gateway
```

The instance joins the tailnet as `kernel-builder-0` about 2 minutes after boot, once
cloud-init has installed packages. Rust and the kernel source finish downloading shortly after.

## SSH in

The instances have no public IP and no inbound security-group rules. You reach them only over
Tailscale, using MagicDNS hostnames (`kernel-builder-0`, `kernel-builder-1`, ...) and the
`~/.ssh/kernel-builder` key, as the `ubuntu` user:

```fish
tailscale ping kernel-builder-0           # optional: check it's on the tailnet
ssh -i ~/.ssh/kernel-builder ubuntu@kernel-builder-0
```

On macOS with the Tailscale app, the CLI is `/Applications/Tailscale.app/Contents/MacOS/Tailscale`.

To skip `-i` and the user name, add this to `~/.ssh/config`:

```
Host kernel-builder-*
    User ubuntu
    IdentityFile ~/.ssh/kernel-builder
    IdentitiesOnly yes
    # Each new instance has a new host key under the same name.
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts.kernel-builder
```

Then `ssh kernel-builder-0`. Because each new instance reuses the name with a new host key, SSH will
warn about a changed key after you recreate one. Clear the old entry with
`ssh-keygen -R kernel-builder-0 -f ~/.ssh/known_hosts.kernel-builder`.

Once you're logged in:

```sh
cloud-init status --wait                  # wait for provisioning (Rust, kernel source) to finish
cd ~/linux && make defconfig && make -j$(nproc)
```

`fetch-latest-kernel` downloads a newer stable release, if there is one, and repoints `~/linux` to it.

You can change the defaults with `-var`, for example `tofu -chdir=instance apply -var instance_count=2 -var instance_type=c7i.8xlarge`.

If Tailscale doesn't come up, use the SSM fallback:
`aws ssm start-session --profile sandbox-admin --target <instance id>` (needs the Session Manager plugin).

## Build an initramfs and boot it in QEMU

`image/` holds the scripts and files for a minimal initramfs: a static BusyBox built from source,
with BusyBox `init` as `/sbin/init` (and `/init`), configured by `image/rootfs/etc/inittab` and
`image/rootfs/etc/init.d/rcS`. Copy it to the builder and build there, after the kernel:

```fish
rsync -a image/ kernel-builder-0:image/
ssh kernel-builder-0
```

```sh
~/image/build-initramfs                   # writes ~/initramfs.cpio.gz
~/image/run-qemu                          # boots ~/linux's bzImage with it; `poweroff` or Ctrl-A X to quit
```

The initramfs has no kernel modules, so anything it needs must be built into the kernel (`=y`).
x86_64 `defconfig` already covers a shell on the serial console; `build-initramfs` warns if one of
the options it relies on is missing. Device nodes come from devtmpfs, which the kernel fills in and
`rcS` mounts on `/dev`. The archive itself holds only `/dev/console`.

## Tear down

```fish
tofu -chdir=instance destroy
```

This removes the instance(s) and the NAT gateway with its Elastic IP and route, which are the only
billable resources. The free VPC, subnets, security group and key pair in `network/` stay in place for
the next `apply`. Because the Tailscale key is ephemeral, the node disappears from your
tailnet by itself shortly after it goes offline.

To remove everything, destroy in reverse order:
`tofu -chdir=instance destroy && tofu -chdir=network destroy && tofu -chdir=iam destroy`.
