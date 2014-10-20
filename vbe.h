// https://github.com/mokafive/grub/blob/upstream/grub-core/video/i386/pc/vbe.c

struct VBEModeInfoBlock
{
  // Mandatory information for all VBE revisions
  u16 ModeAttributes;
  u8 WinAAttributes;
  u8 WinBAttributes;
  u16 WinGranularity;
  u16 WinSize;
  u16 WinASegment;
  u16 WinBSegment;
  u32 WinFuncPtr;
  u16 BytesPerScanLine;
  // Mandatory information for VBE 1.2 and above
  u16 XResolution;
  u16 YResolution;
  u8 XCharSize;
  u8 YCharSize;
  u8 NumberOfPlanes;
  u8 BitsPerPixel;
  u8 NumberOfBanks;
  u8 MemoryModel;
  u8 BankSize;
  u8 NumberOfImagePages;
  u8 Reserved_page;
  // Direct Color fields (required for direct/6 and YUV/7 memory models)
  u8 RedMaskSize;
  u8 RedFieldPosition;
  u8 GreenMaskSize;
  u8 GreenFieldPosition;
  u8 BlueMaskSize;
  u8 BlueFieldPosition;
  u8 RsvdMaskSize;
  u8 RsvdFieldPosition;
  u8 DirectColorModeInfo;
  // Mandatory information for VBE 2.0 and above
  u32 PhysBasePtr;
  u32 OffScreenMemOffset;
  u16 OffScreenMemSize;
  // Mandatory information for VBE 3.0 and above
  u16 LinBytesPerScanLine;
  u8 BnkNumberOfPages;
  u8 LinNumberOfPages;
  u8 LinRedMaskSize;
  u8 LinRedFieldPosition;
  u8 LinGreenMaskSize;
  u8 LinGreenFieldPosition;
  u8 LinBlueMaskSize;
  u8 LinBlueFieldPosition;
  u8 LinRsvdMaskSize;
  u8 LinRsvdFieldPosition;
  u32 MaxPixelClock;
  u8 Reserved[189];
} __attribute__((packed));
