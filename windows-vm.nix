{ config, pkgs, lib, inputs, username, ... }:

let
  # --- Machine-specific values ---

  # Where the VM's disk actually lives. This file is stateful — it's the
  # real Windows install + Dubbing AI, not something Nix rebuilds from
  # scratch. If I ever reformat this host, either:
  #   (a) restore this file from a backup taken beforehand, or
  #   (b) let the activation script below create a fresh empty disk, and
  #       reinstall Windows once (same as before, just triggered by an ISO
  #       already in the domain's boot order instead of virt-manager clicks).
  # For (a) to actually work, this needs to live somewhere that survives a
  # host reformat — a separate drive/partition outside the root filesystem.
  vmDiskPath = "/var/lib/libvirt/images/dubbingai-win10.qcow2";
  vmDiskSizeGB = 60;

  # Windows 10 install ISO. Needs to exist at VM-boot time, kept somewhere
  # permanent (not /tmp).
  winIsoPath = "/home/${username}/isos/Win10.iso";

  # My FIFINE mic's USB vendor/product ID, from `lsusb`:
  # "Bus 006 Device 003: ID 3142:7301 fifinemicrophone.com FIFINE Microphone"
  # — the two hex groups after "ID" are vendorId:productId. Re-check this
  # if I ever swap the mic.
  micVendorId = "0x3142";   # FIFINE Microphone (fifinemicrophone.com)
  micProductId = "0x7301";

  # Same IDs, without the "0x" prefix libvirt XML wants — udev's ATTRS
  # matching on idVendor/idProduct expects bare hex.
  micVendorIdRaw = lib.removePrefix "0x" micVendorId;
  micProductIdRaw = lib.removePrefix "0x" micProductId;

  vmUuid = "6c4f6b8c-9f1a-4e3a-8b7d-2a1e6f9c0d21";  # stable, don't regenerate
  netUuid = "9b6a2f1e-4c3d-4a8b-9e2f-1a7c6d5b8e40"; # stable, don't regenerate

  networkXml = pkgs.writeText "dubbingai-net.xml" ''
    <network>
      <name>dubbingai-net</name>
      <uuid>${netUuid}</uuid>
      <forward mode='nat'/>
      <bridge name='virbr1' stp='on' delay='0'/>
      <ip address='192.168.100.1' netmask='255.255.255.0'>
        <dhcp>
          <range start='192.168.100.2' end='192.168.100.254'/>
        </dhcp>
      </ip>
    </network>
  '';

  domainXml = pkgs.writeText "dubbingai-win10.xml" ''
    <domain type='kvm'>
      <name>dubbingai-win10</name>
      <uuid>${vmUuid}</uuid>
      <memory unit='GiB'>8</memory>
      <currentMemory unit='GiB'>8</currentMemory>
      <vcpu placement='static'>4</vcpu>
      <os firmware='efi'>
        <type arch='x86_64' machine='q35'>hvm</type>
        <boot dev='cdrom'/>
        <boot dev='hd'/>
      </os>
      <features>
        <acpi/>
        <apic/>
      </features>
      <cpu mode='host-passthrough' check='none'/>
      <clock offset='localtime'>
        <timer name='rtc' tickpolicy='catchup'/>
        <timer name='pit' tickpolicy='delay'/>
        <timer name='hpet' present='no'/>
      </clock>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>destroy</on_crash>
      <devices>
        <emulator>${pkgs.qemu_kvm}/bin/qemu-system-x86_64</emulator>

        <disk type='file' device='disk'>
          <driver name='qemu' type='qcow2'/>
          <source file='${vmDiskPath}'/>
          <target dev='sda' bus='sata'/>
        </disk>

        <disk type='file' device='cdrom'>
          <driver name='qemu' type='raw'/>
          <source file='${winIsoPath}'/>
          <target dev='sdb' bus='sata'/>
          <readonly/>
        </disk>

        <interface type='network'>
          <source network='dubbingai-net'/>
          <model type='e1000e'/>
        </interface>

        <input type='tablet' bus='usb'/>
        <input type='keyboard' bus='usb'/>
        <!-- piix3-uhci (USB 1.1), not qemu-xhci: Windows guests routinely
             fail to enumerate full/low-speed USB-audio devices (like the
             FIFINE mic, 12 Mb/s) through an emulated xHCI root hub — QEMU
             shows the device attached, but Windows never sees a connect
             event and Device Manager shows nothing. UHCI matches the mic's
             native speed and reliably fixes this. -->
        <controller type='usb' model='piix3-uhci'/>

        <graphics type='spice' autoport='yes'/>
        <video>
          <model type='qxl' vram='65536'/>
        </video>
        <sound model='ich9'/>
        <channel type='spicevmc'>
          <target type='virtio' name='com.redhat.spice.0'/>
        </channel>

        <!-- My physical mic, passed straight into the VM by USB ID, so
             Windows (and Dubbing AI, and Discord, all running inside it)
             can use it directly. While the VM is running, this device is
             NOT visible on the Linux host — expected, it's exclusively
             claimed by the guest. -->
        <hostdev mode='subsystem' type='usb' managed='yes'>
          <source>
            <vendor id='${micVendorId}'/>
            <product id='${micProductId}'/>
          </source>
        </hostdev>
      </devices>
    </domain>
  '';
in
{
  # KVM/QEMU + libvirt, for running Windows apps (Dubbing AI) that need
  # real kernel-mode drivers Wine can't provide. virt-manager gives me a
  # GUI to create/manage the VM; SPICE handles audio+display passthrough
  # without needing full GPU passthrough (VFIO) for something like a voice
  # changer.
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
    };
  };
  programs.virt-manager.enable = true;

  # Lets me pass a real USB mic/headset straight into the VM if routing
  # through virtio-sound/SPICE isn't enough on its own.
  virtualisation.spiceUSBRedirection.enable = true;

  # The FIFINE mic is dedicated to the Windows VM and should never be
  # claimed by the host's own audio/HID drivers. Without this, Linux
  # auto-binds snd-usb-audio/usbhid the instant the mic enumerates on the
  # bus (normal kernel behavior). That's fine on a clean VM boot, since
  # QEMU's usb-host device forcibly steals the interfaces from the host.
  # But if the mic ever drops and re-enumerates while the VM is already
  # running — a hub power blip, a device reset, or just it sitting
  # connected across an unrelated host config change — the kernel treats
  # that as a fresh connect and re-binds the host drivers immediately,
  # and nothing prompts QEMU to re-steal the interfaces. The guest is
  # then left holding a stale, non-functional reference until the VM is
  # fully stopped and restarted (silently: the mic just vanishes from
  # Windows, with no driver error and nothing in Device Manager).
  # Blacklisting the driver bind here closes that race entirely — the
  # device is never claimed by the host in the first place, on any
  # (re)connect, so QEMU always finds it free to take.
  services.udev.extraRules = ''
    ACTION=="bind", SUBSYSTEM=="usb", DRIVER=="snd-usb-audio", ATTRS{idVendor}=="${micVendorIdRaw}", ATTRS{idProduct}=="${micProductIdRaw}", RUN+="${pkgs.bash}/bin/sh -c 'echo -n $kernel > /sys/bus/usb/drivers/snd-usb-audio/unbind'"
    ACTION=="bind", SUBSYSTEM=="usb", DRIVER=="usbhid", ATTRS{idVendor}=="${micVendorIdRaw}", ATTRS{idProduct}=="${micProductIdRaw}", RUN+="${pkgs.bash}/bin/sh -c 'echo -n $kernel > /sys/bus/usb/drivers/usbhid/unbind'"
  '';

  # So virt-manager doesn't ask for the root password on every routine
  # libvirt action (start/stop/create VM) once I'm in the "libvirtd" group
  # (configuration.nix -> users.users.${username}.extraGroups).
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.libvirt.unix.manage" &&
          subject.isInGroup("libvirtd")) {
        return polkit.Result.YES;
      }
    });
  '';

  # NixVirt: manages libvirtd and declares the domain/network idempotently
  # on every `nixos-rebuild switch`, instead of me clicking through
  # virt-manager by hand every time.
  virtualisation.libvirt.enable = true;

  virtualisation.libvirt.connections."qemu:///system" = {
    networks = [
      {
        definition = networkXml;
        active = true;
      }
    ];
    domains = [
      {
        definition = domainXml;
        active = true; # VM confirmed installed and working
      }
    ];
  };

  # Creates an empty disk image if one doesn't exist yet (first run, or
  # after a reformat where I didn't restore a backup). No-ops once the file
  # is there, so this is safe to leave in permanently.
  system.activationScripts.dubbingaiVmDisk = lib.stringAfter [ "var" ] ''
    mkdir -p "$(dirname ${vmDiskPath})"
    if [ ! -f "${vmDiskPath}" ]; then
      ${pkgs.qemu_kvm}/bin/qemu-img create -f qcow2 "${vmDiskPath}" ${toString vmDiskSizeGB}G
    fi
  '';
}
