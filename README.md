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
| `registry/` | long-lived | ECR repository `microos` for VM images (storage only, cents a month)                    |
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

# 6. ECR repository for VM images
tofu -chdir=registry init
tofu -chdir=registry apply
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

## Build a VM image and publish it as an OCI artifact and an AMI

`image/release` turns the kernel in `~/linux` and the initramfs into a bootable disk, and publishes it
two ways. Build the kernel first, then on the builder run:

```sh
~/image/release                           # or --no-oci / --no-ami to skip one
```

It runs these steps, each of which also works on its own:

1. `build-initramfs` writes `~/initramfs.cpio.gz`.
2. `build-disk` writes `~/microos.img`: a 1 GiB raw GPT disk with a single EFI system partition. The
   partition holds a unified kernel image (UKI, made with `ukify`): the kernel, initramfs and command
   line (`console=ttyS0 panic=-1`) in one EFI executable at `EFI/BOOT/BOOTX64.EFI`. UEFI firmware
   boots that path with no bootloader. The kernel needs `CONFIG_EFI_STUB=y`, which x86_64 `defconfig` has.
3. `push-oci` pushes the disk to the ECR repository as an OCI artifact (with `oras`). The artifact has
   one layer, `microos.qcow2`, and is tagged `<kernel version>-<UTC time>` and `latest`.
4. `make-ami` uploads the raw disk to an EBS snapshot with `coldsnap`, without attaching a volume, and
   registers it as an x86_64 AMI that boots with UEFI. It prints the AMI ID.

`~/image/run-vm` boots `~/microos.img` in QEMU with OVMF firmware, the same way EC2 will.

### Run it on your Mac

```fish
brew install qemu oras
aws sso login --profile sandbox-admin
image/fetch-vm                            # pulls :latest to ./microos.qcow2; or: image/fetch-vm <tag> <dir>
image/run-vm microos.qcow2                # `poweroff` or Ctrl-A X to quit
```

The guest is x86_64, so on Apple silicon QEMU emulates it in software. That's slower than native,
but fine for a shell. `run-vm` opens the disk copy-on-write, so the file never
changes. To list the tags that exist:
`aws ecr list-images --profile sandbox-admin --region us-west-2 --repository-name microos`.

### Run it on EC2

The AMI needs a Nitro instance type, because those support UEFI boot. It has no network
configuration, and `defconfig` has no ENA driver, so watch it on the serial console. Launch it into
the private subnet:

```fish
set ami ami-...                           # printed by make-ami / release
aws ec2 run-instances --profile sandbox-admin --region us-west-2 \
    --image-id $ami --instance-type t3.micro \
    --subnet-id (tofu -chdir=network output -raw private_subnet_id) \
    --security-group-ids (tofu -chdir=network output -raw security_group_id) \
    --metadata-options HttpTokens=required \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=microos}]' \
    --query 'Instances[0].InstanceId' --output text
aws ec2 get-console-output --profile sandbox-admin --region us-west-2 --latest --output text \
    --instance-id i-...
```

For an interactive shell, use the EC2 serial console. It's off by default; turn it on once per region with
`aws ec2 enable-serial-console-access`, then connect from the instance's page in the EC2 console.
Terminate the instance when you're done.

AMIs and their snapshots aren't in any tofu stack, and they stay until you delete them. Each snapshot
is tiny. To remove an AMI, run `aws ec2 deregister-image --delete-associated-snapshots --image-id ...`.

## Tear down

```fish
tofu -chdir=instance destroy
```

This removes the instance(s) and the NAT gateway with its Elastic IP and route, which are the only
billable resources. The free VPC, subnets, security group and key pair in `network/` stay in place for
the next `apply`. Because the Tailscale key is ephemeral, the node disappears from your
tailnet by itself shortly after it goes offline.

To remove everything, destroy in reverse order:
`tofu -chdir=instance destroy && tofu -chdir=registry destroy && tofu -chdir=network destroy && tofu -chdir=iam destroy`.
