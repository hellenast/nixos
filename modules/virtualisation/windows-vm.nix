{ pkgs, lib, inputs, username, ... }:

# A Windows 10 VM (KVM/QEMU via libvirt), declared with NixVirt. It exists
# for one Windows-only app, the "Dubbing AI" voice changer, which needs real
# kernel-mode drivers that Wine can't provide. The USB mic is passed
# straight through to the guest; the processed voice comes back to the host
# through the virtual mic in audio-routing.nix. Manual steps (ISO, guest
# tools, routing): docs/virtualisation.md.

let
  # --- Machine-specific values ---

  # The VM's disk: the actual Windows install, real state that Nix can't
  # rebuild. After a host reformat, either restore it from a backup, or let
  # the activation script at the bottom create an empty one and reinstall
  # Windows (the ISO is already first in the boot order).
  vmDiskPath = "/var/lib/libvirt/images/dubbingai-win10.qcow2";
  vmDiskSizeGB = 60;

  # Windows 10 install ISO. Has to exist whenever the VM boots, so keep it
  # somewhere permanent.
  winIsoPath = "/home/${username}/isos/Win10.iso";

  # The FIFINE USB mic's vendor/product id, from `lsusb`:
  #   Bus 006 Device 003: ID 3142:7301 fifinemicrophone.com FIFINE Microphone
  # The two hex groups after "ID" are vendorId:productId. Re-check them if
  # the mic is ever swapped.
  micVendorId = "0x3142";   # FIFINE Microphone (fifinemicrophone.com)
  micProductId = "0x7301";

  # The same ids without the "0x" prefix: libvirt's XML wants "0x3142",
  # udev's ATTRS{idVendor} matching wants bare "3142".
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
  imports = [ inputs.nixvirt.nixosModules.default ];

  # Manage VMs without sudo (applies after logging out and back in).
  users.users.${username}.extraGroups = [ "libvirtd" ];

  # KVM/QEMU + libvirt. SPICE carries display and audio, which is plenty for
  # a voice changer — no GPU passthrough (VFIO) needed. virt-manager is the
  # GUI for poking at the VM by hand.
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
    };
    # The default, "suspend", saves the running VM's memory on host
    # shutdown and restores it on the next boot. That snapshot records the
    # mic's USB bus/device address, which can change across a reboot, so
    # the restore intermittently fails ("Unable to find device 006.003 in
    # list of active USB devices") and the mic stays broken. A clean guest
    # shutdown means every boot is a cold start instead.
    onShutdown = "shutdown";
  };
  programs.virt-manager.enable = true;

  # At boot, the udev rule below (unbinding the host's drivers from the mic)
  # and libvirtd autostarting the VM happen at about the same time. If QEMU
  # claims the mic before the unbind finishes, the claim silently half-fails:
  # QEMU reports it attached, but never owns the audio interfaces, and the
  # mic doesn't appear in Windows until it's detached/reattached. Waiting
  # for udev to settle before libvirtd starts guarantees the unbind is done.
  systemd.services.libvirtd.preStart = ''
    ${pkgs.systemd}/bin/udevadm settle --timeout=30
  '';

  # Lets virt-manager/SPICE clients hand other USB devices to the VM on the
  # fly (the mic itself is passed through permanently, above).
  virtualisation.spiceUSBRedirection.enable = true;

  # The mic belongs to the VM, so the host's snd-usb-audio/usbhid drivers
  # are unbound from it whenever they bind. QEMU takes the device from the
  # host on VM start anyway, but if the mic re-enumerates while the VM is
  # running (hub power blip, device reset), the kernel rebinds the host
  # drivers and nothing makes QEMU take it back — the mic silently vanishes
  # from Windows until a full VM restart. With this rule the host never
  # holds on to it.
  services.udev.extraRules = ''
    ACTION=="bind", SUBSYSTEM=="usb", DRIVER=="snd-usb-audio", ATTRS{idVendor}=="${micVendorIdRaw}", ATTRS{idProduct}=="${micProductIdRaw}", RUN+="${pkgs.bash}/bin/sh -c 'echo -n $kernel > /sys/bus/usb/drivers/snd-usb-audio/unbind'"
    ACTION=="bind", SUBSYSTEM=="usb", DRIVER=="usbhid", ATTRS{idVendor}=="${micVendorIdRaw}", ATTRS{idProduct}=="${micProductIdRaw}", RUN+="${pkgs.bash}/bin/sh -c 'echo -n $kernel > /sys/bus/usb/drivers/usbhid/unbind'"
  '';

  # No polkit password prompt for routine libvirt actions (start/stop/create
  # VM) for members of the "libvirtd" group (added at the top).
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.libvirt.unix.manage" &&
          subject.isInGroup("libvirtd")) {
        return polkit.Result.YES;
      }
    });
  '';

  # NixVirt defines the network and VM above in libvirt on every rebuild,
  # idempotently, so nothing has to be set up in virt-manager by hand.
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
        active = true; # NixVirt starts it (at boot and on rebuild) if it isn't running
      }
    ];
  };

  # Creates an empty disk image if there isn't one yet (first install, or a
  # reformat without a restored backup). Does nothing once the file exists.
  system.activationScripts.dubbingaiVmDisk = lib.stringAfter [ "var" ] ''
    mkdir -p "$(dirname ${vmDiskPath})"
    if [ ! -f "${vmDiskPath}" ]; then
      ${pkgs.qemu_kvm}/bin/qemu-img create -f qcow2 "${vmDiskPath}" ${toString vmDiskSizeGB}G
    fi
  '';
}
