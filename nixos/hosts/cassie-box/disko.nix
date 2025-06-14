# Disko configuration for cassie-box
# This file defines the automated partitioning scheme for installation
{
  disko.devices = {
    disk = {
      main = {
        device = "/dev/disk/by-id/ata-CT2000BX500SSD1_2425E8B9A602";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "1G";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "500G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
            data = {
              size = "498G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/data1";
              };
            };
          };
        };
      };
      disk2 = {
        device = "/dev/disk/by-id/nvme-WD_BLACK_SN770_2TB_241958806974";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            main = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/data2";
              };
            };
          };
        };
      };
    };
  };
}
