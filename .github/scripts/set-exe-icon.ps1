# Embeds an application icon in a Windows executable.
#
# Upstream Ladybird has no icon resource for Windows: the Qt UI sets the window icon at run time, so a
# running window shows it, but a pinned taskbar item, Explorer and Task Manager read the icon from the
# .exe file and show a generic one. This renders the given PNG at the standard icon sizes and stores it
# as the executable's icon resource (RT_GROUP_ICON 1), with the Windows resource update API.

param(
    [Parameter(Mandatory)] [string] $Exe,
    [Parameter(Mandatory)] [string] $Png,
    [int[]] $Sizes = @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ExeIconResource
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr BeginUpdateResource(string fileName, bool deleteExistingResources);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool UpdateResource(IntPtr update, IntPtr type, IntPtr name, ushort language, byte[] data, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool EndUpdateResource(IntPtr update, bool discard);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibraryEx(string fileName, IntPtr reserved, uint flags);
    [DllImport("kernel32.dll")]
    static extern IntPtr FindResource(IntPtr module, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll")]
    static extern bool FreeLibrary(IntPtr module);

    const int RT_ICON = 3;
    const int RT_GROUP_ICON = 14;
    const uint LOAD_LIBRARY_AS_DATAFILE = 0x2;

    static Exception Failure()
    {
        return new InvalidOperationException("Windows error " + Marshal.GetLastWin32Error());
    }

    // images: PNG-encoded icon images (supported in icon resources since Windows Vista), sizes: their sizes.
    public static void Set(string exe, byte[][] images, int[] sizes)
    {
        IntPtr update = BeginUpdateResource(exe, false);
        if (update == IntPtr.Zero)
            throw Failure();

        bool done = false;
        try {
            // GRPICONDIR followed by one GRPICONDIRENTRY per image, which refers to the RT_ICON resource by id.
            byte[] group = new byte[6 + 14 * images.Length];
            BitConverter.GetBytes((ushort)0).CopyTo(group, 0);             // reserved
            BitConverter.GetBytes((ushort)1).CopyTo(group, 2);             // type: icon
            BitConverter.GetBytes((ushort)images.Length).CopyTo(group, 4); // image count
            for (int i = 0; i < images.Length; i++) {
                ushort id = (ushort)(i + 1);
                if (!UpdateResource(update, (IntPtr)RT_ICON, (IntPtr)id, 0, images[i], (uint)images[i].Length))
                    throw Failure();
                int entry = 6 + 14 * i;
                group[entry + 0] = (byte)(sizes[i] >= 256 ? 0 : sizes[i]); // width (0 means 256)
                group[entry + 1] = (byte)(sizes[i] >= 256 ? 0 : sizes[i]); // height
                group[entry + 2] = 0;                                      // palette colors
                group[entry + 3] = 0;                                      // reserved
                BitConverter.GetBytes((ushort)1).CopyTo(group, entry + 4);  // color planes
                BitConverter.GetBytes((ushort)32).CopyTo(group, entry + 6); // bits per pixel
                BitConverter.GetBytes((uint)images[i].Length).CopyTo(group, entry + 8);
                BitConverter.GetBytes(id).CopyTo(group, entry + 12);
            }
            if (!UpdateResource(update, (IntPtr)RT_GROUP_ICON, (IntPtr)1, 0, group, (uint)group.Length))
                throw Failure();
            done = true;
        } finally {
            if (!EndUpdateResource(update, !done) && done)
                throw Failure();
        }
    }

    public static bool Has(string exe)
    {
        IntPtr module = LoadLibraryEx(exe, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (module == IntPtr.Zero)
            throw Failure();
        try {
            return FindResource(module, (IntPtr)1, (IntPtr)RT_GROUP_ICON) != IntPtr.Zero;
        } finally {
            FreeLibrary(module);
        }
    }
}
'@

$Exe = (Resolve-Path $Exe).Path
$source = [System.Drawing.Image]::FromFile((Resolve-Path $Png).Path)
try {
    $images = foreach ($size in $Sizes) {
        $bitmap = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        # Clamp at the edges, so that scaling does not blend in transparent pixels from outside the image.
        $attributes = New-Object System.Drawing.Imaging.ImageAttributes
        $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $graphics.DrawImage($source, (New-Object System.Drawing.Rectangle 0, 0, $size, $size),
            0, 0, $source.Width, $source.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $graphics.Dispose()
        $stream = New-Object System.IO.MemoryStream
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        , $stream.ToArray()
    }
} finally {
    $source.Dispose()
}

[ExeIconResource]::Set($Exe, [byte[][]] $images, [int[]] $Sizes)
if (-not [ExeIconResource]::Has($Exe)) { throw "$Exe has no icon resource after embedding one" }
Write-Host "Embedded a $($Sizes.Count)-size icon from $(Split-Path -Leaf $Png) in $(Split-Path -Leaf $Exe)"
