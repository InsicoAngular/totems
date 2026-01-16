using System.Runtime.InteropServices;

public static class RawPrintHelper
{
    [DllImport("winspool.drv", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool StartDocPrinter(IntPtr hPrinter, int Level, [In] ref DOCINFO pDocInfo);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

    public static bool SendBytesToPrinter(string printerName, byte[] bytes)
    {
        IntPtr hPrinter = IntPtr.Zero;
        bool success = false;

        try
        {
            if (OpenPrinter(printerName, out hPrinter, IntPtr.Zero))
            {
                DOCINFO docInfo = new DOCINFO
                {
                    pDocName = "Impresión PDF",
                    pDataType = "RAW"
                };

                if (StartDocPrinter(hPrinter, 1, ref docInfo))
                {
                    IntPtr pBytes = Marshal.AllocHGlobal(bytes.Length);
                    Marshal.Copy(bytes, 0, pBytes, bytes.Length);

                    success = WritePrinter(hPrinter, pBytes, bytes.Length, out _);

                    Marshal.FreeHGlobal(pBytes);
                    EndDocPrinter(hPrinter);
                }
            }
        }
        finally
        {
            if (hPrinter != IntPtr.Zero)
            {
                ClosePrinter(hPrinter);
            }
        }

        return success;
    }

    private struct DOCINFO
    {
        [MarshalAs(UnmanagedType.LPStr)]
        public string pDocName;

        [MarshalAs(UnmanagedType.LPStr)]
        public string pOutputFile;

        [MarshalAs(UnmanagedType.LPStr)]
        public string pDataType;
    }
}
